#!/bin/bash

## crontab -e
## @reboot      /usr/local/bin/free-mem-cache.sh >/tmp/free-mem-cache.log 2>&1
## */20 * * * * /usr/local/bin/free-mem-cache.sh >/tmp/free-mem-cache.log 2>&1

show_memory_info() {
  echo '--------------------'
  free -wh
  echo '--------------------'
}
printf "[%s]\n" "$(date)"
show_memory_info

# Get memory information
read -r _ total_mem _ free_mem _ <<<"$(free | grep 'Mem:')"
# Output memory information
printf "Free memory : %d MB\n" "$((free_mem / 1024))"
printf "Total memory: %d MB\n" "$((total_mem / 1024))"
# Clear cache if free memory is less than 20% of total memory
if [ "$free_mem" -lt "$((total_mem / 5))" ]; then
  sync
  if echo 3 >/proc/sys/vm/drop_caches; then
    sync
    echo "Caches cleared successfully"
    show_memory_info
  else echo "Failed to clear caches"; fi
else echo "Memory is sufficient"; fi

printf "[%s] Done.\n" "$(date)"
echo '--------------------'
## The end
