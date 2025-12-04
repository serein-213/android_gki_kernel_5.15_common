# Workflow Verification Checklist

## Pre-deployment Verification

### ✅ Completed Items

- [x] Created `build_gki.yml` workflow file
- [x] Created `README_zh.md` documentation
- [x] Updated `.gitignore` to allow `.github` directory
- [x] Fixed YAML syntax errors
- [x] Validated YAML structure with Python yaml module
- [x] Implemented correct timestamp handling
  - [x] Set `KBUILD_BUILD_TIMESTAMP` environment variable
  - [x] Set `SOURCE_DATE_EPOCH` environment variable
  - [x] Pass timestamps to Bazel via `--action_env`
- [x] Configured build environment
  - [x] Repository initialization
  - [x] Dependency installation
  - [x] Tool installation (repo, mkbootimg)
- [x] Applied configuration fixes
  - [x] ZRAM modularization
  - [x] task_is_booster export
  - [x] KMI symbol list update
  - [x] stamp.bzl patch
- [x] Artifact generation
  - [x] Kernel Image (uncompressed)
  - [x] Image.gz (gzip compressed)
  - [x] Image.lz4 (lz4 compressed)
  - [x] boot.img creation
  - [x] AnyKernel3 package
  - [x] Build information file
  - [x] Release notes
- [x] Build verification
  - [x] Kernel image verification
  - [x] Version string extraction
  - [x] Timestamp validation
- [x] Documentation
  - [x] Chinese README with usage instructions
  - [x] Troubleshooting guide
  - [x] Flashing methods
  - [x] Build summary generation

## Ready for Testing

### Manual Trigger Test

The workflow can be tested by:

1. **Via GitHub UI**:
   - Go to Actions tab
   - Select "Build GKI Kernel"
   - Click "Run workflow"
   - Select branch: `copilot/create-workflow-script-for-kernel`
   - Click "Run workflow" button

2. **Via Push** (automatic trigger):
   - Push any commit to `copilot/create-workflow-script-for-kernel` branch
   - Workflow will start automatically

3. **Via Pull Request** (automatic trigger):
   - Create PR to `copilot/create-workflow-script-for-kernel` branch
   - Workflow will start automatically

### Expected Workflow Behavior

1. **Duration**: Approximately 60-90 minutes (depends on GitHub Actions runner)
2. **Disk Usage**: ~30-40 GB (workflow includes disk cleanup)
3. **Success Indicators**:
   - All steps complete successfully
   - Artifacts uploaded
   - Build summary shows correct timestamp (not 1970)
   - No YAML syntax errors

### Artifacts to Verify

After successful build, check:

1. **Artifact Package**: `GKI-Kernel-5.15-{version}`
2. **Contents**:
   - [ ] Image (uncompressed kernel)
   - [ ] Image.gz (gzip compressed)
   - [ ] Image.lz4 (lz4 compressed)
   - [ ] boot.img (flashable boot image)
   - [ ] AnyKernel3-GKI-5.15.zip (AnyKernel3 package)
   - [ ] build_info.txt (build metadata)
   - [ ] RELEASE_NOTES.md (release documentation)
   - [ ] *.ko files (kernel modules, if any)

### Timestamp Verification

The kernel version string should show actual build time, not:
- ❌ `Thu Jan  1 00:00:00 UTC 1970`
- ✅ Should show actual date/time like: `Wed Dec  4 12:34:56 UTC 2024`

This can be verified by:
1. Checking the "Extract Kernel Version" step output
2. Examining the build summary
3. Using `strings Image | grep "Linux version"`

## Known Considerations

### Build Time
- First build: 60-90 minutes (full sync of build tools)
- Subsequent builds: Similar (GitHub Actions doesn't persist workspace)

### Disk Space
- Workflow includes automatic cleanup of unnecessary files
- Build requires ~30-40 GB total space
- GitHub Actions provides sufficient space

### Network
- Downloads ~10-15 GB of build tools and dependencies
- Requires stable internet connection

### Bazel Cache
- Not persistent across workflow runs
- Each run starts fresh

## Troubleshooting Scenarios

### If Workflow Fails

1. **Check workflow logs** in GitHub Actions
2. **Common issues**:
   - Disk space (already handled by cleanup step)
   - Network timeout (repo sync may fail)
   - ABI compatibility (configuration fixes applied)
   - YAML syntax (already validated)

### If Timestamp is Still Wrong

1. Check environment variables in logs
2. Verify Bazel received `--action_env` flags
3. Check `stamp.bzl` patch was applied

### If Artifacts Missing

1. Check "Package Kernel Artifacts" step
2. Verify kernel build completed
3. Check file paths in workflow

## Success Criteria

✅ The workflow is considered successful if:

1. All steps complete without errors
2. Artifacts are uploaded
3. Kernel version string shows correct timestamp
4. All expected files are present in artifact package
5. Build summary is generated

## Next Steps

After verification:

1. Test workflow with manual trigger
2. Review build artifacts
3. Verify timestamp in kernel version
4. Test on actual device (optional)
5. Document any issues or improvements needed

---

**Status**: Ready for Testing
**Last Updated**: 2024-12-04
**Branch**: copilot/create-workflow-script-for-kernel
