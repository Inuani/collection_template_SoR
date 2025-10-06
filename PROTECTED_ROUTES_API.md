# Protected Routes API Documentation

## Overview

The Protected Routes system allows you to protect specific URL paths with NFC authentication. When a user tries to access a protected route, they must scan an authorized NFC tag with a valid CMAC to gain access.

---

## Key Concepts

- **Protected Route**: A URL path that requires NFC authentication
- **CMAC**: Cryptographic Message Authentication Code from NFC tags
- **Scan Count**: Number of successful scans for a protected route
- **Path Matching**: Routes are matched using text containment (e.g., `/item` matches `/item/1`, `/item/2`, etc.)

---

## Data Structure

```motoko
type ProtectedRoute = {
    path: Text;           // URL path to protect
    cmacs_: [Text];       // Array of authorized CMAC values
    scan_count_: Nat;     // Number of successful authentications
};
```

---

## Admin Functions (Owner Only)

### Add Protected Route

Creates a new protected route. Initially has no authorized CMACs.

```bash
dfx canister call <canister> add_protected_route '("/path/to/protect")'
```

**Parameters:**
- `path`: Text - The URL path to protect

**Returns:** `Bool` - `true` if added successfully, `false` if route already exists

**Example:**
```bash
dfx canister call collection add_protected_route '("/item/1")'
# Returns: (true)
```

---

### Update Route CMACs (Replace)

Replaces all CMACs for a route with new ones.

```bash
dfx canister call <canister> update_route_cmacs '("/path", vec {"cmac1"; "cmac2"})'
```

**Parameters:**
- `path`: Text - The protected route path
- `cmacs`: [Text] - Array of new CMAC values (replaces existing)

**Returns:** `Bool` - `true` if updated, `false` if route doesn't exist

**Example:**
```bash
dfx canister call collection update_route_cmacs '("/item/1", vec {"ABC123"; "DEF456"})'
# Returns: (true)
```

---

### Append Route CMACs (Add More)

Adds additional CMACs to a route without removing existing ones.

```bash
dfx canister call <canister> append_route_cmacs '("/path", vec {"new_cmac1"; "new_cmac2"})'
```

**Parameters:**
- `path`: Text - The protected route path
- `cmacs`: [Text] - Array of CMACs to append

**Returns:** `Bool` - `true` if appended, `false` if route doesn't exist

**Example:**
```bash
dfx canister call collection append_route_cmacs '("/item/1", vec {"GHI789"})'
# Returns: (true)
```

---

### Update Scan Count

Manually update the scan count for a route (usually handled automatically).

```bash
dfx canister call <canister> update_route_scan_count '("/path", 10)'
```

**Parameters:**
- `path`: Text - The protected route path
- `count`: Nat - New scan count value

**Returns:** `Bool` - `true` if updated, `false` if route doesn't exist

---

## Query Functions (Public)

### Get Route

Retrieve full details of a specific protected route.

```bash
dfx canister call <canister> get_route '("/path")'
```

**Returns:** `?ProtectedRoute` - The route details or `null` if not found

**Example:**
```bash
dfx canister call collection get_route '("/item/1")'
# Returns: (opt record { 
#   path = "/item/1"; 
#   cmacs_ = vec {"ABC123"; "DEF456"}; 
#   scan_count_ = 5 : nat 
# })
```

---

### Get Route CMACs

Get only the authorized CMACs for a route.

```bash
dfx canister call <canister> get_route_cmacs '("/path")'
```

**Returns:** `[Text]` - Array of CMACs (empty array if route doesn't exist)

**Example:**
```bash
dfx canister call collection get_route_cmacs '("/item/1")'
# Returns: (vec {"ABC123"; "DEF456"})
```

---

### List Protected Routes (Full Details)

Get all protected routes with complete information including all CMACs.

```bash
dfx canister call <canister> listProtectedRoutes
```

**Returns:** `[(Text, ProtectedRoute)]` - Array of tuples (path, route details)

**Example:**
```bash
dfx canister call collection listProtectedRoutes
# Returns: (vec {
#   record { "/item/1"; record { path = "/item/1"; cmacs_ = vec {"ABC123"; "DEF456"}; scan_count_ = 5 : nat } };
#   record { "/item/2"; record { path = "/item/2"; cmacs_ = vec {"XYZ789"}; scan_count_ = 3 : nat } };
# })
```

---

### List Protected Routes Summary (Path & Count Only) ⭐ NEW

Get all protected routes with **only path and scan count** - no CMAC data included.

```bash
dfx canister call <canister> listProtectedRoutesSummary
```

**Returns:** `[(Text, Nat)]` - Array of tuples (path, scan_count)

**Example:**
```bash
dfx canister call collection listProtectedRoutesSummary
# Returns: (vec {
#   record { "/item/1"; 5 : nat };
#   record { "/item/2"; 3 : nat };
#   record { "/item/3"; 0 : nat };
# })
```

**Use Case:** 
- When you want to see which routes are protected and their usage statistics
- When you don't need the CMAC data (which can be lengthy)
- For dashboard displays showing route activity
- For monitoring and analytics

---

## Complete Workflow Example

```bash
# 1. Add a protected route
dfx canister call collection add_protected_route '("/premium/content")'
# Returns: (true)

# 2. Add authorized CMACs (from NFC tags)
dfx canister call collection update_route_cmacs '(
  "/premium/content", 
  vec {"CMAC_FROM_TAG_1"; "CMAC_FROM_TAG_2"}
)'
# Returns: (true)

# 3. Check the route was configured
dfx canister call collection get_route '("/premium/content")'
# Returns: (opt record { 
#   path = "/premium/content"; 
#   cmacs_ = vec {"CMAC_FROM_TAG_1"; "CMAC_FROM_TAG_2"}; 
#   scan_count_ = 0 : nat 
# })

# 4. User scans NFC tag and accesses URL
# System automatically increments scan_count_ if CMAC matches

# 5. Check summary statistics (without exposing CMACs)
dfx canister call collection listProtectedRoutesSummary
# Returns: (vec { record { "/premium/content"; 12 : nat } })

# 6. Add more authorized tags later
dfx canister call collection append_route_cmacs '(
  "/premium/content",
  vec {"CMAC_FROM_TAG_3"}
)'
# Returns: (true)

# 7. View full details if needed
dfx canister call collection listProtectedRoutes
```

---

## Access Control

### Admin Functions (Require Owner Permission)
- `add_protected_route`
- `update_route_cmacs`
- `append_route_cmacs`
- `update_route_scan_count`

### Public Query Functions
- `get_route`
- `get_route_cmacs`
- `listProtectedRoutes`
- `listProtectedRoutesSummary` ⭐

---

## How Authentication Works

1. **Route Protection**: Admin adds a route path to protect
2. **CMAC Registration**: Admin adds authorized CMAC values to the route
3. **User Access**: User tries to access the protected URL
4. **NFC Scan**: User scans their NFC tag (generates CMAC)
5. **Verification**: System checks if CMAC is in the authorized list
6. **Grant/Deny**: If match found, access granted and scan count incremented
7. **Tracking**: Scan count helps monitor usage and activity

---

## Best Practices

### Security
- Keep CMACs confidential - only share with trusted users
- Regularly rotate CMACs for high-security routes
- Monitor scan counts for unusual activity
- Use specific paths (e.g., `/item/1`) rather than broad paths (e.g., `/`)

### Management
- Use descriptive route paths for easy identification
- Document which physical NFC tags correspond to which CMACs
- Use `append_route_cmacs` to add tags without disrupting existing access
- Use `listProtectedRoutesSummary` for monitoring dashboards

### Performance
- Use `listProtectedRoutesSummary` instead of `listProtectedRoutes` when you only need statistics
- Protected routes are stored in a HashMap for efficient lookups
- Path matching uses text containment for flexibility

---

## Comparison: Full List vs Summary

### `listProtectedRoutes` - Full Details
**When to use:**
- Admin panel requiring complete route configuration
- Auditing which CMACs have access to which routes
- Debugging authentication issues
- Exporting/backing up route configurations

**Example output:**
```motoko
(vec {
  record { 
    "/item/1"; 
    record { 
      path = "/item/1"; 
      cmacs_ = vec {"CMAC1"; "CMAC2"; "CMAC3"}; 
      scan_count_ = 25 : nat 
    } 
  }
})
```

### `listProtectedRoutesSummary` - Path & Count Only ⭐
**When to use:**
- Dashboard showing route activity/usage
- Monitoring which routes are most accessed
- Quick overview without sensitive CMAC data
- Public-facing statistics (scan counts are not sensitive)
- Performance-critical queries (smaller payload)

**Example output:**
```motoko
(vec {
  record { "/item/1"; 25 : nat };
  record { "/item/2"; 10 : nat };
  record { "/item/3"; 0 : nat }
})
```

---

## Troubleshooting

### Route not found
```bash
# Check if route exists
dfx canister call collection get_route '("/path")'
# Returns: (null) if not found

# List all routes
dfx canister call collection listProtectedRoutesSummary
```

### Authentication failing
```bash
# Check if route has CMACs configured
dfx canister call collection get_route_cmacs '("/path")'
# Returns: (vec {}) if no CMACs registered

# Verify CMAC format and spelling
dfx canister call collection get_route '("/path")'
```

### Permission denied
```bash
# Admin functions require owner identity
# Check your identity:
dfx identity whoami

# Switch to owner identity if needed:
dfx identity use <owner_identity>
```

---

## Migration Guide

If you were using `listProtectedRoutes` just to get scan statistics:

**Before:**
```bash
# Had to parse through all CMACs to get scan count
dfx canister call collection listProtectedRoutes
```

**After:**
```bash
# Now get clean path + count data directly
dfx canister call collection listProtectedRoutesSummary
```

---

## API Reference

### Public Types
```motoko
type ProtectedRoute = {
    path: Text;
    cmacs_: [Text];
    scan_count_: Nat;
};
```

### Admin Functions
- `add_protected_route(path: Text) : async Bool`
- `update_route_cmacs(path: Text, cmacs: [Text]) : async Bool`
- `append_route_cmacs(path: Text, cmacs: [Text]) : async Bool`
- `update_route_scan_count(path: Text, count: Nat) : async Bool`

### Query Functions
- `get_route(path: Text) : async ?ProtectedRoute`
- `get_route_cmacs(path: Text) : async [Text]`
- `listProtectedRoutes() : async [(Text, ProtectedRoute)]`
- `listProtectedRoutesSummary() : async [(Text, Nat)]` ⭐

---

## Support

For issues or questions:
1. Check this documentation
2. Review `src/nfc_protec_routes.mo` source code
3. Check canister logs: `dfx canister logs <canister_name>`
4. Verify your identity has admin permissions