# Automated deployment for stations

We use this repository when setting up new stations. It's not intended to be used by itself, as it requires binaries and scripts built to a certain configuration. This repository is public for the sake of making things easy.

## Prerequisites
1. Create a user that's going to run the station automation. In this example we use `liq-user`
2. Make `liq-user` a sudoer
## Batteries not included:
This build script assumes you have a Docker container already built. Refer to Confluence for instructions how to build.
## How to use
1. Get the repository: `cd ~/ && git clone https://github.com/fremen-fi/a26-setup-helpers.git`
2. Run the initial build script: `bash ~/a26-setup-helpers/production/build.sh`. The computer will reboot after this step.
    * The following information is required for this step:
        * HLS directory username, should be `liq-user` in this example
        * HLS access token: Apache only serves files if this `X-CDN-Token` is present in the request headers. Add this token to your CDN request.
        * CIFS username
        * CIFS password
        * CIFS host
        * GitHub username
        * GitHub PAT (Personal Access Token)
3. Once the server has restarted, run the startup script: `bash ~/a26-setup-helpers/production/start.sh`
    * The following information is required for this step:
        * The username who you chose to be the owner of the HLS repository (in this example, `liq-user`)
        * GitHub username
        * GitHub repository name
    * Once this step has finished, you will end up with a running Docker container named `radio-10` if you didn't modify the `production/compose.yml` file.
