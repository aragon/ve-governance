// read from the file test/fork/bpt-leaderboard.json
import fs from "fs";

export const leaderboardToStakers = JSON.parse(
  fs.readFileSync("./test/fork/bpt-leaderboard.json", "utf8"),
);
// extract the addresses only

const data = leaderboardToStakers.bpt.map(({ address }) => address);
// write back to stakers.json in the same folder
fs.writeFileSync("./test/fork/stakers.json", JSON.stringify(data, null, 2));
