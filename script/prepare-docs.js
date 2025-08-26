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
    settings: { outputSelection: { "*": { "*": ["*"], "": ["ast"] } } },
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

  const templatesPath = "docs/templates";
  const apiPath = "docs/modules/api";

  const helpers = require(path.resolve(ROOT_DIR, "docs/templates/helpers"));

  // overwrite the functions.
  helpers.version = () => `${version}`;
  helpers.githubURI = () => repository.url;

  console.log(output)

  const config = {
    outputDir: `${apiPath}/pages`,
    sourcesDir: path.resolve(ROOT_DIR, "src"),
    templates: templatesPath,
    exclude: ["mocks", "test"],
    pageExtension: ".adoc",
    collapseNewlines: true,
    pages: (_, file, config) => {
      return REPO_NAME + config.pageExtension;
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
