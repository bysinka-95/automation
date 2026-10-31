# automation

Shell scripts for automating routine tasks in Linux. Coursework repository (USM, "Automation of scripts").

Each lab lives in its own folder on its own branch, merged into `main`:

| Folder  | Branch  | Contents                                                                                         |
| ------- | ------- | ------------------------------------------------------------------------------------------------ |
| `lab01` | `lab01` | `disk_usage.sh` — directory disk usage monitor with email alerts                                 |
| `lab02` | `lab02` | `currency_exchange_rate.py` — exchange rate client for the currency service, saves rates as JSON |
| `lab03` | `lab03` | cron in Docker — runs the lab02 script on a schedule (daily MDL→EUR, weekly MDL→USD)             |
| `lab04` | `lab04` | Jenkins in Docker — controller, SSH agent with PHP, pipeline that runs PHPUnit tests             |

Every lab folder has its own `README.md` with the script description, usage and examples.
