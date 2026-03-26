#!/bin/bash

#1. Print current user, home directory, and shell

echo "User: $USER"
echo "Home: $HOME"
echo "Shell: $SHELL"

#2. Check if /var/log exists

[[ -d /var/log ]] && echo "/var/log exists" || echo "/var/log deos NOT exist"

#3. Count total files in the current directory

file_count=$(find . -maxdepth 1 -type f | wc -l)
echo " Files in current directory: $file_count"

#4. Display date and time in custom format (YYYY-MM-DD HH:MM:SS)

date "+Date: %Y-%m-%d Time: %H:%M:%S"

#5. Save system info to system-info.txt

{
        echo "System Information"
        echo "=================="
        echo "User: $USER"
        echo "Home: $HOME"
        echo "Shell: $SHELL"
        echo "Hostname: $(hostname)"
        echo "OS : $(uname -o)"
        echo "kernel: $(uname -r)"
        echo "Uptime: $(uname -p)"
} > system-info.txt

echo "System info saved to system-info.txt"


#!/bin/bash

# Thresholds
DISK_THRESHOLD=80
MEM_THRESHOLD=85

# Slack webhook (optional)
SLACK_WEBHOOK="https://hooks.slack.com/services/XXXX/YYYY/ZZZZ"

# CPU Usage: 
# -b → batch mode (non-interactive, suitable for scripts), 
# -n1 → run only once and exit
# $8 → represents the idle CPU percentage (id)
# -F. → split the number at the decimal point
# {print $1} → take only the integer part
CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | awk -F. '{print $1}')
echo "CPU Usage: $CPU_LOAD%"

# Memory Usage
# awk '/Mem/ { ... }'  Filters the line that starts with Mem
# printf → command to print formatted output
    # "%.0f" → formatting rule
    # %f → floating-point number (decimal number)
    # .0 → show 0 digits after the decimal point
    # So it means: round to the nearest whole number
# $2 → total memory
# $3 → used memory
MEM_USAGE=$(free | awk '/Mem/ {printf "%.0f", $3/$2 * 100}')
echo "Memory Usage: $MEM_USAGE%"

if [ "$MEM_USAGE" -gt "$MEM_THRESHOLD" ]; then
    ALERT_MSG="ALERT: Memory usage is high: $MEM_USAGE%"
    echo "$ALERT_MSG"
    # Optional Slack alert
    # curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$ALERT_MSG\"}" $SLACK_WEBHOOK
fi

# Disk Usage
# df -hP -> show disk usage in human-readable format and POSIX output
# awk -v -> allows us to pass a shell variable (threshold) into the awk script
# threshold="$DISK_THRESHOLD" -> become the variable "threshold" inside awk
# NR>1 -> skip the header line and gsub("%","",$5) -> remove the % sign from the usage value
# %s -> string placeholder, %d -> integer placeholder
#%s -> file location liek (/ or /home) and %s%% means 30% to add one % we have to add %%
df -hP | awk -v threshold="$DISK_THRESHOLD" '
NR>1 {
    gsub("%","",$5)
    if ($5+0 > threshold) {
        printf "ALERT: Disk usage on %s is %s%%\n", $6, $5
    } else {
        printf "%s usage is %s%%\n", $6, $5
    }
}'

# Top 5 CPU consuming processes
# ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu → lists all processes with specific columns and sorts them by CPU usage in descending order
# -e → select all processes and -o custom output format
# ppid -> parent process ID 
echo "Top 5 Processes:"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 6

# Running Services
# systemctl list-units --type=service --state=running → lists all running services
echo "Running Services:"
systemctl list-units --type=service --state=running | awk '{print $1}' | head -n 10


#ss -tuln → shows all listening ports with numeric output
# awk 'NR>1 {print $5}' → extracts the 5th column (which contains the address:port) and skips the header line 
echo "Open Ports:"
ss -tuln | awk 'NR>1 {print $5}' | sort | uniq

echo "Health check completed"





└─$ cat 12.sh
#!/bin/bash

LOG_DIR="/var/log/app"
ARCHIVE_DIR="/var/log/archive"
DAYS_TO_KEEP=7

mkdir -p "$ARCHIVE_DIR"

# Compress logs older than 2 days but not currently in use
find "$LOG_DIR" -type f -name "*.log" -mtime +2 ! -exec lsof {} \; | while read -r FILE; do
    gzip -c "$FILE" > "$ARCHIVE_DIR/$(basename "$FILE").gz"
    if [ $? -eq 0 ]; then
        rm -f "$FILE"
        echo "Archived and removed: $FILE"
    else
        echo "FAILED to archive: $FILE"
    fi
done

# Delete archived logs older than DAYS_TO_KEEP
find "$ARCHIVE_DIR" -type f -mtime +"$DAYS_TO_KEEP" -name "*.gz" -exec rm -f {} \; -print

echo "Log rotation and cleanup completed"




