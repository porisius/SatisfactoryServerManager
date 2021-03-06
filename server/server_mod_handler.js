const exec = require("child_process").exec
const path = require("path");
const schedule = require('node-schedule');

const Config = require("./server_config");
const logger = require("./server_logger");

const {
    getInstalls,
    SatisfactoryInstall,
    getAvailableSMLVersions,
    getLatestSMLVersion,
    getAvailableMods,
    getMod,
    getModVersions
} = require("satisfactory-mod-manager-api")

class SSM_Mod_Handler {
    constructor() {

    }

    init() {
        logger.info("[Mod_Handler] [INIT] - Mod Handler Initialized");

        getInstalls().then(sf_installs => {
            const foundInstall = sf_installs.find(el => el.installLocation = Config.get("satisfactory.server_location"))

            if (foundInstall != null) {
                this.SML_API = foundInstall;
            }
        })

        this.startScheduledJobs();
    }

    startScheduledJobs() {
        schedule.scheduleJob('30 * * * *', () => {
            if (Config.get("mods.enabled") && Config.get("mods.autoupdate")) {
                this.autoUpdateAllMods();
            }
        });
    }

    getSMLInfo() {
        return new Promise((resolve, reject) => {

            this.SML_API._getInstalledSMLVersion().then(res => {
                const infoObject = {
                    state: "not_installed",
                    version: ""
                }

                if (typeof res != 'undefined' && res != "") {
                    infoObject.state = "installed"
                    infoObject.version = res;
                }

                resolve(infoObject);
            })
        });
    }

    getModsInstalled() {
        return new Promise((resolve, reject) => {

            this.SML_API._getInstalledMods().then(res => {
                const resArr = [];

                for (let i = 0; i < res.length; i++) {
                    const mod = res[i];

                    const ModObj = {
                        name: mod.name,
                        id: mod.mod_id,
                        version: mod.version
                    }

                    resArr.push(ModObj);
                }

                resolve(resArr);
            })
        });
    }

    installModVersion(modid, version) {
        return new Promise((resolve, reject) => {

            logger.info("[MOD_HANDLER] [INSTALL] - Installing Mod: " + modid + " (" + version + ")");
            this.SML_API.installMod(modid, version).then(() => {
                logger.info("[MOD_HANDLER] [INSTALL] - Installed Mod: " + modid + " (" + version + ")");
                resolve()
            }).catch(err => {
                logger.error("[MOD_HANDLER] [INSTALL] - Installing Mod Failed!");
                reject(err);
            })
        });
    }

    uninstallMod(modid) {
        return new Promise((resolve, reject) => {
            let currentMod = null;
            this._getModsInstalled().then(mods => {
                currentMod = mods.find(el => el.id == modid);

                if (currentMod != null) {
                    logger.info("[MOD_HANDLER] [UNINSTALL] - Uninstalling Mod: " + currentMod.id + " (" + currentMod.version + ")");
                    return this.SML_API.uninstallMod(modid);
                }
                return;
            }).then(() => {
                logger.info("[MOD_HANDLER] [UNINSTALL] - Uninstalled Mod: " + currentMod.id + " (" + currentMod.version + ")");
                resolve();
            }).catch(err => {
                logger.error("[MOD_HANDLER] [UNINSTALL] - Uninstalling Mod Failed!");
                reject(err);
            })
        })
    }

    // TODO: Placeholder for SMLAPI updateMod Function
    updateMod(modid) {
        return new Promise((resolve, reject) => {
            logger.info("[MOD_HANDLER] [INSTALL] - Updating Mod: " + modid);
            this.SML_API.updateMod(modid).then(() => {
                logger.info("[MOD_HANDLER] [INSTALL] - Updated Mod: " + modid + "!");
                resolve();
            })
        })
    }

    installSMLVersion(req_version) {
        return new Promise((resolve, reject) => {
            getAvailableSMLVersions().then(versions => {
                const sml_version = versions.find(el => el.version == req_version)

                if (sml_version == null) {
                    logger.error("[MOD_HANDLER] [INSTALL] - Installing SML Failed!");
                    reject("Error: SML version doesn't exist!")
                    return;
                }

                logger.info("[MOD_HANDLER] [INSTALL] - Installing SML " + req_version + " ...")
                this.SML_API.installSML(sml_version.version).then(() => {
                    logger.info("[MOD_HANDLER] [INSTALL] - Installed SML " + req_version + "!")
                    resolve()
                }).catch(err => {
                    logger.error("[MOD_HANDLER] [INSTALL] - Installing SML Failed!");
                    reject(err);
                })


            }).catch(err => {
                logger.error("[MOD_HANDLER] [INSTALL] - Installing SML Failed!");
                reject(err);
            })
        });
    }

    installSMLVersionLatest() {
        return new Promise((resolve, reject) => {
            logger.info("[MOD_HANDLER] [INSTALL] - Installing SML ...")
            getLatestSMLVersion().then(sml_version => {
                return this.installSMLVersion(sml_version.version)
            }).then(res => {
                resolve(res)
            }).catch(err => {
                logger.error("[MOD_HANDLER] [INSTALL] - Installing SML Failed!");
                reject(err);
            })
        })
    }

    getFicsitSMLVersions() {
        return new Promise((resolve, reject) => {
            getAvailableSMLVersions().then(versions => {
                resolve(versions)
            }).catch(err => {
                reject(err);
            })
        });
    }

    getFicsitModList() {
        return new Promise((resolve, reject) => {
            getAvailableMods().then(mods => {
                const resArr = [];

                for (let i = 0; i < mods.length; i++) {
                    const mod = mods[i];

                    let latest_version = mod.versions[0];

                    if (latest_version == null) continue;

                    resArr.push({
                        id: mod.id,
                        name: mod.name,
                        latest_version: latest_version.version
                    })
                }
                resolve(resArr);
            }).catch(err => {
                reject(err);
            })
        })
    }

    getFicsitModInfo(modid) {
        return new Promise((resolve, reject) => {
            const ModInfo = {
                id: null,
                name: "",
                logo: "",
                versions: []
            }
            getMod(modid).then(mod => {
                ModInfo.id = mod.id;
                ModInfo.name = mod.name;
                ModInfo.logo = mod.logo;

                return getModVersions(modid)
            }).then(Mod_versions => {
                ModInfo.versions = Mod_versions;
                resolve(ModInfo);
            }).catch(err => {
                reject(err);
            })
        });
    }

    autoUpdateAllMods() {
        this.getModsInstalled().then(mods => {

            logger.info("[Mod_Handler] [AUTOUPDATE] - Updating " + mods.length + " mods");

            for (let i = 0; i < mods.length; i++) {
                const mod = mods[i];
                this.updateMod(mod.id)
            }

            logger.info("[Mod_Handler] [AUTOUPDATE] - Updated all mods!");
        })
    }
}
const ssm_mod_handler = new SSM_Mod_Handler();
module.exports = ssm_mod_handler;