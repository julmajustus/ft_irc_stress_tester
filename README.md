# IRC Destroyer

**IRC Destroyer** (a.k.a. `ircd_destroyer.sh`) is a modular, script-based stress-testing tool for IRC servers. Its main purpose is to generate large numbers of connections and a wide variety of IRC protocol actions, to reveal bugs or performance issues in IRC daemons and networks.

> **Warning**: This script is deliberately designed to place extreme load on an IRC server—even potentially *break* it. Please **only** use it in a controlled environment (such as a local test server). Using it against public or unauthorized servers is unethical and may be illegal.

---

## Features

- **Multiple Test Modes**:  
  - `b`: Basic commands (join, privmsg, whois, etc.)  
  - `j`: Join tests (join multiple, invalid, or repeated channels)  
  - `p`: Part tests  
  - `P`: Privmsg tests (sending messages to channels, users, self, invalid targets)  
  - `m`: Mode tests (try valid and invalid modes, set/bulk modes, etc.)  
  - `i`: Invalid commands (garbled or non-IRC commands)  
  - `A`: Auth (simple PASS/NICK/USER)  
  - `x`: Incorrect auth sequence (NICK/USER before PASS, or wrong PASS)  
  - `r`: Re-auth (attempting to re-register after correct auth)  
  - `u`: Unfinished auth (missing NICK)  
  - `g`: Garbage (random data + partial IRC commands)  
  - `a`: All of the above, in sequence (run each test in its own connection).

- **Connection Stress**: Automatically spawn *up to thousands* of IRC clients in parallel or serial bursts.  
- **Configurable Delays**: Slow down the rate of new connections with `-s <seconds>` to avoid saturating your network instantly.  
- **Info Gathering**: Collects a list of current server channels and users before running the tests, making tests more representative of a live network scenario.

---

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/<your-username>/irc_destroyer.git
   cd irc_destroyer
   ```

2. Ensure ircd_destroyer.sh is executable:
   ```bash
   chmod +x ircd_destroyer.sh
   ```

3. Verify your system has:
   - bash (4.x or higher is fine)
   - netcat (nc)
   - mktemp (usually included on most Linux/BSD systems)

---

## Usage
   ```bash
   ./ircd_destroyer.sh -S <server> -P <port> -p <password> [options]
   ```

**Required arguments:**

   - -S <server>: IRC server host (e.g. localhost)
   - -P <port>: IRC server port (e.g. 6667)
   - -p <password>: Server password (e.g. securepassword)

**Optional:**  

   - -t <test_mode>: One-letter test mode from [b j p P m i A x r u g]. Use a to run them all (default: a)
   - -c <connections>: Number of client connections to spawn (default: 10)
   - -s <seconds>: Sleep time between each connection (default: 0.5)
   - -T <seconds>: Netcat read/write timeout (default: 5)

---

## Examples

   Run all tests once each, with minimal stress:
   ```bash
   ./ircd_destroyer.sh -S localhost -P 6667 -p supersecret -t a -c 1
   ```

   Hit the server with 1000 basic tests:
   ```bash
   ./ircd_destroyer.sh -S localhost -P 6667 -p supersecret -t b -c 1000
   ```

   Run join tests with 50 connections, 0.01s delay:
   ```bash
   ./ircd_destroyer.sh -S localhost -P 6667 -p supersecret -t j -c 50 -s 0.01
   ```
---

## How It Works

1. The script first gathers information about the server’s channels, users, and modes using a temporary “infoBot”.
   
2. Depending on the chosen test mode(s), the script dynamically generates and pipes IRC commands into nc (netcat).

3. Each spawned test connection:
      - Authenticates with the server using your supplied password (unless it’s specifically testing invalid/incorrect auth).
      - Performs the relevant join, part, message, mode, or invalid actions.
      - Finally quits, allowing netcat to close the connection.

By default, CONN_COUNT parallel connections each run the same script code, effectively “hammering” the server with repeated sets of commands.

---

## Disclaimer
This tool is highly disruptive. It can and likely will crash or saturate an IRC server if used at high concurrency levels. Only use it on servers you own or where you have explicit permission to perform stress tests. The author(s) are not responsible for misuse.
