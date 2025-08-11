You have been provided a summary of a static analyser with a series of findings.

Your job here is to orchestrate a series of agents in building proof-of-concept exploits for the relevant finding.

You will limit yourself to only high and criticial findings. If none are found, note this and exit.

First, read the OVERVIEW.md file to familiarise yourself with the architecture of our system.

Next, for each relevant finding:

1. Create a prompt that extracts the finding.
2. Grab the specification documents and the source code for the affected contracts and write them to the prompt
3. Pass the prompt to a sub-agent that will attempt to craft an exploit, you can attach the results of 1 and 2 to 03-exploit.md in this directory.
