# Build EchoRelay without installing Xcode on your Mac

EchoRelay includes a GitHub Actions workflow that uses GitHub's hosted macOS runner to compile the app. The runner already has Xcode installed.

## Easiest method

1. Create a new GitHub repository, for example `EchoRelay`.
2. On the repository page, choose **Add file → Upload files**.
3. Upload the contents of this folder, including `.github/workflows/build-macos.yml`.
4. Commit to the `main` branch.
5. Open the repository's **Actions** tab and select **Build EchoRelay for macOS**.
6. After the workflow finishes, open the workflow run and download the **EchoRelay-macOS** artifact.
7. Unzip `EchoRelay-macOS.zip` and move `EchoRelay.app` to Applications.
8. On first launch, macOS may require you to Control-click/right-click the app and choose **Open**, because this build is not Apple-notarized.

The workflow builds an unsigned universal app for Apple Silicon and Intel Macs. GitHub's hosted macOS runners provide Xcode, so no local Xcode installation is needed.

## Important

EchoRelay requires macOS 14.4 or later in this version. The first launch also requires the Screen & System Audio Recording permission described in the main README.
