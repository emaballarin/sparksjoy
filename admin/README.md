# Administrative Scripts

Scripts for DGX Spark system administration and user management.

## Scripts

### `create_user.sh`

Creates new unprivileged users with home directories and default configuration.

**Usage:**

```bash
# Interactive mode
sudo ./create_user.sh

# Command-line mode
sudo ./create_user.sh username
```

**Features:**

- Creates user with home directory and default skeleton
- Generates secure random temporary password
- Requires sudo/wheel group membership
- Sets bash as default shell

**Output:** Displays the username and temporary password for the new user.
