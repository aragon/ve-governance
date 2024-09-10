starting_time = 100
current_time = starting_time
interval = 10

for seconds in range(30):
    current_time += 1
    elapsed_in_interval = current_time % interval
    time_until_next_interval = interval - elapsed_in_interval

    if elapsed_in_interval == 0:
        next_deposit = current_time
    else:
        next_deposit = current_time + time_until_next_interval

    print("Current time:             ", current_time)
    print("Elapsed in interval:      ", elapsed_in_interval)
    print("Time until next interval: ", time_until_next_interval)
    print("Next deposit:             ", next_deposit)
    print("")




