Line by line

Write the slopes

- calculate the bias and slope - we have that

Fetch dslopes

- The change here is now that we initialise a newDslope variable
  - remember this is global, so we fetch the oldLocked.end which syncs to the checkpoint
  - In velo:
    - if the end of the new lock == 0, keep @ newDSlope 0
    - if the end of the new lock is the same as the end of the old one just grab the eold one
  - really what's happening is we are grabbing both slope changes here

init the globla points

- We fetch a global point and we fetch a global epoch

  - in our case it's probably a checkpoint? Alternatively we could use the clock

- last checkpoint is just the timestamp associated with the global supply update

- copy across the data into memory - if there's no last point initialise it

- block interpolation that we don't need

The for loop backfill

This writes history as part of the checkpoint

- t_i is the floored week -> we again could use the clock here
- we loop over up to 255 weeks (max uint8)
- add a week (in our case interval)
- init the change in slope
- ceil the t_i to now if above OR
  - fetch the slope change at that point
- evaluate the new bias based on the slope change
  - We need to check this works with our getBias function based on the old bias
    - In the linear case, should do tho
- add the dslope that's fetched from the slope histories, this will be zero if t_i == block.timestamp
- floor the bias and slope - we don't need to do this as ours is increasing
- set the checkpoint as the week aligned cp

- break if we are at the block timestamp
- increment the point index and write the lastPoint

Updating the latest global point

- this part updates the global slope and bias based on the marginal change from the new user
- This will need a rework for us, the slope will definitely increase with a new deposit and decrease with a withdrawal
- The bias is the same

Updating slopes

- if the end is in the future, we have some schedullling to do
- remove the old slope from the dslope

How does it work in our, increasing case

We likely need the old point and the new point
However in our case, we have currently 2 states

1. I am creating a new lock

   - I write 1 point when my bias and slope increases total suppy
   - I write 1 point when the dslope change hits (at max)

2. I am exiting a lock
   - I write 1 point when my exit is scheduled
   - I unwind a dslope change if it is yet to occur

We don't support modifications. So descope for now => for delegation that's a different story

# implementation

We determine 'exiting' as amount == 0

ergo we need both the old and new locked in order to establish the dslope changes but easy otherwise

Step 1: determine the basic constraints - Are we exiting or depositing? - if depositing, we don't need the exit adjustment

Step 2: compute bias and coefficients - this only works for linear so need to think of an idomatic way to handle this

Step 3: backfill history - starting from the last recorded checkpoint, iterate over the intervals and back fill history - being careful to snap to the next week after the checkpoint not to overrwrite data - here we also build up the current GlobalPoint

Step 4: add the incremental change of the token to the global point

Step 5: Write the global point

Step 6: Schedule / unschedule the slope changes

Step 7: Write the token Point

The main outstanding question - scheduled writes

suppose we have a user who writes

TODOs:

decide and review scheduled adjustments
fix the bug with the warmup period
retire the bias if not needed
do a full test of the curve in other logic stuff
Create a test on the user point with some hard coded values
Create an exploit where the user double counts by depositing AT the boundary
Multiple same block updates and if that's possible
Test boundary updates: - Scheduled updates are processed - what about individual updates
