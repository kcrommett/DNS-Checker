# DNS Checker

A powerful command-line tool for verifying DNS records and testing DNS propagation across multiple servers.

## Features

- **DNS Record Verification**: Compare actual DNS records against expected values
- **DNS Propagation Testing**: Check if DNS changes have propagated across multiple DNS servers
- **Multiple Record Types**: Support for A, AAAA, CNAME, MX, TXT, SRV, and other DNS record types
- **Special Handling**: Enhanced processing for SPF and DMARC records in TXT records
- **Multiple DNS Servers**: Query multiple DNS providers in a single test
- **Clean Table Output**: Concise, well-formatted results for easy reading
- **Detailed Verbose Mode**: See complete query information when needed

## Requirements

- Bash shell environment
- `dig` command-line tool (part of the BIND utilities)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/dns-checker.git
   cd dns-checker
   ```

2. Make the script executable:
   ```bash
   chmod +x DNS-Checker.sh
   ```

## Usage

### Basic DNS Verification

```bash
./DNS-Checker.sh [config_file]
```

If no config file is specified, the script defaults to `dns-config.txt`.

### Propagation Testing

```bash
./DNS-Checker.sh -p example.com -t A
```

This checks the A records for example.com across multiple DNS servers to verify propagation.

### Command-Line Options

```
  -f, --fresh              Force fresh DNS lookups (bypass cache)
  -s, --server SERVER      Specify DNS server to query (default: 1.1.1.1)
  -q, --queries COUNT      Perform multiple queries and check consistency
  -m, --multi-server       Use multiple DNS servers for queries
  -p, --propagation DOMAIN Test DNS propagation for a specific domain
  -t, --type TYPE          Record type for propagation test (default: A)
  -d, --dns-file FILE      Specify a custom DNS servers file
  -v, --verbose            Enable verbose output
  -h, --help               Show help message
```

## Configuration Files

### DNS Config File Format

The DNS configuration file (`dns-config.txt` by default) specifies the records to check:

```
RECORD_TYPE | HOSTNAME | EXPECTED_VALUE
```

Example:
```
A | example.com | 192.0.2.1
CNAME | www.example.com | example.com.
TXT | example.com | "v=spf1 include:_spf.example.net -all"
```

Special configuration options:
```
#DNS_SERVER=8.8.8.8
```

### DNS Servers File Format

The DNS servers file (`dns-servers.txt` by default) lists DNS servers to use for propagation tests:

```
Server Name|IP Address
```

Example:
```
Cloudflare|1.1.1.1
Google|8.8.8.8
OpenDNS|208.67.222.222
```

## Examples

### Verify All Records in Configuration

```bash
./DNS-Checker.sh
```

### Check with Verbose Output

```bash
./DNS-Checker.sh --verbose
```

### Test Propagation of AAAA Records

```bash
./DNS-Checker.sh -p example.com -t AAAA -v
```

### Use Multiple DNS Servers with a Specific Config

```bash
./DNS-Checker.sh -m custom-config.txt
```

### Test TXT Record Propagation with Custom DNS Servers

```bash
./DNS-Checker.sh -p example.com -t TXT -d custom-dns-servers.txt
```

## Troubleshooting

- If you see "Command not found" errors, ensure the script has execute permissions
- For "dig: command not found", install BIND utilities (varies by OS)
- If the script can't find configuration files, verify they exist in the current directory

## License

[MIT License](LICENSE)