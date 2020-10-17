# Flag Manager

![GitHub All Releases](https://img.shields.io/github/downloads/ivenuss/flag-manager/total) ![GitHub last commit](https://img.shields.io/github/last-commit/ivenuss/flag-manager) ![GitHub repo size](https://img.shields.io/github/repo-size/ivenuss/flag-manager) 

## Description
Adds user to database with admin flag to specific duration & whenever user joins to server he obtains admin flag

## Database preview

![ddisp](https://i.imgur.com/WCDjsGB.png)

## Installation
connect to your mysql in ``databases.cfg``
```sh
"flag_manager"
{
    "driver"                        "mysql"
    "host"                          "localhost"
    "database"                      ""
    "user"                          ""
    "pass"                          ""
}
```

## ConVars
```sh
sm_fm_adminflag "b" //Admin flags with access to admin commands.
```

## Commands
* `sm_addflag <steamid64> <flag> <duration> <unit>`
* `sm_extendflag <steamid64> <duration> <unit>`
* `sm_deleteflag <steamid64>`

## Usage
Allowed units: `second`, `minute`, `hour`, `day`, `week`, `month`, `year`

* `sm_addflag 45228196148486128 abo 5 day`
* `sm_extendflag 45228196148486128 1 month`
* `sm_deleteflag 45228196148486128`