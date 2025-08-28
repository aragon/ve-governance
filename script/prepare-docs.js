const docgen = require("solidity-docgen/dist/main");

const { readdir } = require("node:fs/promises");
const { join } = require("node:path");
const path = require("path");
const fs = require("fs-extra");
const solc = require("solc");
const { execSync } = require("child_process");
const { version, repository } = require("../package.json");

const ROOT_DIR = path.resolve(__dirname, "..");
const REPO_NAME = "ve-governance";

// or node
const RUNTIME = "bun";
const README = 'README.adoc'

const walk = async (dirPath) =>
  Promise.all(
    await readdir(dirPath, { withFileTypes: true }).then((entries) =>
      entries.map((entry) => {
        const childPath = join(dirPath, entry.name);
        return entry.isDirectory() ? walk(childPath) : childPath;
      }),
    ),
  );

// Get remappings dynamically from Forge
const getRemappings = () => {
  try {
    return execSync("forge remappings", { encoding: "utf8" })
      .split("\n")
      .filter(Boolean)
      .map((remap) => remap.split("="));
  } catch (error) {
    console.error("Error fetching remappings:", error);
    return [];
  }
};

const remappings = getRemappings();

// Resolve imports using Forge remappings
function resolveImports(filePath) {
  for (const [key, value] of remappings) {
    if (filePath.startsWith(key)) {
      const remappedPath = path.join(
        ROOT_DIR,
        value,
        filePath.replace(key, ""),
      );
      if (fs.existsSync(remappedPath)) {
        return { contents: fs.readFileSync(remappedPath, "utf8") };
      }
    }
  }
  return { error: `File not found: ${filePath}` };
}

const compile = async (filePaths) => {
  const compilerInput = {
    language: "Solidity",
    sources: filePaths.reduce((input, fileName) => {
      const relativePath = path.relative(path.resolve(ROOT_DIR, "src"), fileName);
      const source = fs.readFileSync(fileName, "utf8");
      return { ...input, [relativePath]: { content: source } };
    }, {}),
    settings: { 
      outputSelection: { 
        "*": {
          "*": ["abi", "devdoc", "userdoc", "metadata", "storageLayout"],
          "": ["ast"]
        } 
      }}
  };

  console.log("Compiling contracts...");

  return {
    output: JSON.parse(
      solc.compile(JSON.stringify(compilerInput), { import: resolveImports }),
    ),
    input: compilerInput,
  };
};

async function main() {
  const contractPath = path.resolve(ROOT_DIR, "src");
  const allFiles = await walk(contractPath);

  const solFiles = allFiles.flat(Number.POSITIVE_INFINITY).filter((item) => {
    return path.extname(item).toLowerCase() == ".sol";
  });

  const { input, output } = await compile(solFiles);

  // `output.sources` contain files with `absolutePath` such as: "voting/AddressGaugeVoter.sol" 
  // instead of `/Desktop/.../ve-governance/src/voting/AddressGaugeVoter.sol which solidity docgen
  // can't handle. So rewrite absolute paths for each contract output compilation.
  if (output.sources) {
    for (const [relativePath, sourceData] of Object.entries(output.sources)) {
      if (sourceData.ast && sourceData.ast.absolutePath) {
        sourceData.ast.absolutePath = path.resolve(ROOT_DIR, "src", relativePath);
      }
    }
  }

  const templatesPath = "docs/templates";
  const apiPath = "docs/modules/api";

  const helpers = require(path.resolve(ROOT_DIR, "docs/templates/helpers"));

  // overwrite the functions.
  helpers.version = () => `${version}`;
  helpers.githubURI = () => repository.url;
  helpers.readmePath = (opts) => {
    // In case no README was found in the respective folder 
    // of the contract, then return the default README.adoc
    if(opts.data.root.id == 'README.adoc') {
      return 'src/' + README;
    } 

    // otherwise, return the contract's respective readme(i.e delegation.adoc)
    return 'src/' + opts.data.root.id.replace(/\.adoc$/, '') + '/' + README;
  }

  const config = {
    outputDir: `${apiPath}/pages`,
    sourcesDir: path.resolve(ROOT_DIR, "src"),
    templates: templatesPath,
    // The output.souces contain each contract as duplicated(one without `@` prefix and one with `@`)
    // This is because we use remappings and import contracts with `@`. Without excluding them here,
    // Solidity docgen still tries to find `README.adoc` located near them, which can never be found
    // as such paths don't exist in reality. So we exclude them one by one for now.
    exclude: [
      "mocks", 
      "test", 
      "forge-std", 
      "@openzeppelin", 
      "@solmate", 
      "@clock", 
      "@curve", 
      "@escrow", 
      "@delegation", 
      "@factory", 
      "@libs", 
      "@lock", 
      "@queue", 
      "@setup", 
      "@voting", 
      "@test", 
      "@foundry-upgrades", 
      "@ensdomains", 
      "@aragon"
    ],
    pageExtension: ".adoc",
    collapseNewlines: true,
    pages: (_, file, config) => {
      // For each contract file, find the closest README.adoc and return its location as the output page path.
      const sourcesDir = path.resolve(config.root, config.sourcesDir);
      let dir = path.resolve(config.root, file.absolutePath);

      while (dir.startsWith(sourcesDir)) {
        dir = path.dirname(dir);
        if (fs.existsSync(path.join(dir, README))) {
          const relative = path.relative(sourcesDir, dir);
          // If the `README` is NOT located in the respective folder of the contract, 
          // it resolves to find it in the `src` in which case `relative` variable
          // ends up empty string, so if that's the case, we return `README.adoc`
          // so later on, page handlebar can find it.
          if(relative == '') {
            return README;
          }

          // Otherwise, `relative` is the name of the folder in which contract is located.
          // I.e if the EscrowIVotesAdapter is in delegation folder, below would return
          // and generate `delegation.adoc`.
          return relative + config.pageExtension;
        }
      }
    },
  };

  const o = await output;

  console.log("Generating docs...");
  await docgen.main([{ input, output: o }], config);
  const navOutput = execSync(`${RUNTIME} script/gen-nav.js ${apiPath}/pages`, {
    encoding: "utf8",
  });

  // Write the output to the target file
  const targetFilePath = `${apiPath}/nav.adoc`;
  console.log("Writing nav to", targetFilePath);
  fs.writeFileSync(targetFilePath, navOutput, "utf8");

  fs.rm(templatesPath, { recursive: true, force: true }, () => { });
}

main()
  .then(() => {
    console.log("Docs generated successfully");
  })
  .catch((error) => {
    console.error("Error generating docs", error);
    process.exit(1);
  });
