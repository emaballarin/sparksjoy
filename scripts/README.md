# System Utility Scripts

Shell scripts for system maintenance and optimization.

## Scripts

### `cacheflush.sh`

Manually flushes system memory caches.

**Usage:**

```bash
sudo ./cacheflush.sh
```

**Purpose:** Clears page cache, dentries, and inodes. Useful for benchmarking or freeing memory.

**Requirements:** Sudo access

---

### `updateall.sh`

Performs comprehensive system updates.

**Usage:**

```bash
sudo ./updateall.sh
```

**Purpose:** Updates system packages (apt) and firmware (fwupdmgr).

**Requirements:** Sudo access, Ubuntu-based system
