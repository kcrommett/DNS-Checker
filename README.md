
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