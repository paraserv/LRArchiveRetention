# Production-Scale Testing Strategy

## 🎯 Testing Philosophy

**Simulate Real Production Environments:**
- Large datasets (10,000+ files)
- Substantial data volumes (10+ GB)
- Realistic directory structures
- Production-scale performance characteristics

## 📂 Approved Test Data Locations

### **Only Two Target Locations:**

1. **Local Storage**: `D:\LogRhythmArchives\Inactive`
   - **Purpose**: Local disk performance testing
   - **Scenario**: On-premises archive storage
   - **Dataset**: 398+ folders, 14,825+ files, 32.9+ GB

2. **NAS Storage**: `\\10.20.1.7\LRArchives`
   - **Purpose**: Network storage performance testing
   - **Scenario**: Centralized NAS archive storage
   - **Dataset**: Similar scale to local storage

### **No Additional Test Directories:**
- ❌ No ExecutionTest directories
- ❌ No small isolated test datasets
- ❌ No separate directories for different test modes

## 🔧 Production-Scale Testing Approach

### **Test Data Generation**
```powershell
# Generate substantial test data using GenerateTestData.ps1
.\GenerateTestData.ps1 -RootPath "D:\LogRhythmArchives\Inactive" -FolderCount 500 -MinFiles 10 -MaxFiles 50 -MaxFileSizeMB 5 -MaxSizeGB 2

# For NAS testing (with credentials)
.\GenerateTestData.ps1 -RootPath "\\10.20.1.7\LRArchives" -CredentialTarget "NAS_CREDS" -FolderCount 500 -MinFiles 10 -MaxFiles 50 -MaxFileSizeMB 5 -MaxSizeGB 2
```

### **Dry-Run Testing**
```powershell
# Test against complete dataset - all files processed
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 90
```

### **Execution Mode Testing**
```powershell
# Test against complete dataset - all files evaluated, conservative retention
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 1000 -Execute
```

## 🛡️ Safe Execution Testing Strategy

### **Conservative Retention Periods**
- **1000+ Days**: Only deletes very old files (from 2022 or earlier)
- **Result**: Processes entire dataset, deletes minimal files
- **Safety**: Preserves majority of test data while proving functionality

### **Full Dataset Processing**
- **Scans**: All 14,825+ files evaluated for retention
- **Processes**: Complete dataset for performance metrics
- **Deletes**: Only ancient files that meet retention criteria
- **Performance**: Production-scale processing demonstrated

### **Production Simulation Benefits**
1. **Realistic Performance**: True production-scale metrics
2. **Memory Usage**: Real memory consumption patterns
3. **I/O Load**: Actual disk/network I/O characteristics
4. **Scaling**: Demonstrates ability to handle large archives
5. **Reliability**: Proves stability under production loads

## 📊 Expected Test Results

### **Dry-Run Mode**
- **Files Processed**: 14,825+ files (complete dataset)
- **Performance**: 3,000+ files/second processing rate
- **Data Volume**: 32.9+ GB processed
- **Time**: ~5 seconds for complete dataset

### **Execution Mode**
- **Files Scanned**: 14,825+ files (complete dataset)
- **Files Deleted**: Subset of very old files (varies by retention policy)
- **Performance**: 3,000+ files/second processing rate
- **Safety**: Majority of test data preserved

### **NAS Testing**
- **Network Performance**: Realistic network I/O patterns
- **Credential Handling**: Secure authentication to network shares
- **Latency Impact**: True network storage performance characteristics

## 🎯 Key Testing Objectives

### **Performance Validation**
- Process large datasets (10,000+ files) efficiently
- Maintain high throughput (3,000+ files/second)
- Handle substantial data volumes (10+ GB)
- Demonstrate production-ready scalability

### **Safety Verification**
- Conservative retention policies prevent data loss
- Comprehensive logging of all operations
- Robust error handling under load
- Minimal disruption to test datasets

### **Production Readiness**
- Realistic workload simulation
- Enterprise-scale dataset processing
- Network storage compatibility
- Audit trail compliance

## 📋 Testing Checklist

### **Pre-Test Setup**
- [ ] Deploy scripts to `C:\LR\Scripts\LRArchiveRetention\`
- [ ] Generate substantial test data (500+ folders, 10,000+ files)
- [ ] Verify WinRM/SSH connectivity
- [ ] Configure NAS credentials if testing network storage

### **Dry-Run Testing**
- [ ] Test 7-day retention (should warn about minimum)
- [ ] Test 30-day retention (should warn about minimum)
- [ ] Test 90-day retention (should process without warnings)
- [ ] Test 1000-day retention (should process minimal files)
- [ ] Verify comprehensive logging
- [ ] Measure performance metrics

### **Execution Mode Testing**
- [ ] Test with 1000+ day retention (conservative)
- [ ] Verify all files are scanned
- [ ] Confirm only ancient files are deleted
- [ ] Validate retention action logging
- [ ] Verify directory cleanup
- [ ] Measure execution performance

### **NAS Testing**
- [ ] Set up network credentials
- [ ] Generate test data on NAS
- [ ] Test dry-run mode on network storage
- [ ] Test execution mode on network storage
- [ ] Verify network performance characteristics

## 🚀 Production Benefits

This testing strategy provides:
- **Confidence**: Proven performance at production scale
- **Reliability**: Demonstrated stability under realistic loads
- **Accuracy**: True performance metrics for capacity planning
- **Safety**: Verified operation with large datasets
- **Compliance**: Complete audit trails for enterprise requirements

**Result**: Production-ready system validated against realistic enterprise archive scenarios.