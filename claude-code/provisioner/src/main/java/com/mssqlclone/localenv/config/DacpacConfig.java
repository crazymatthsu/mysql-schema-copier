package com.mssqlclone.localenv.config;

import java.nio.file.Path;
import java.util.Map;

/** Where extracted DACPACs land, and which upstream server they are extracted from. */
public record DacpacConfig(Path outputDir, String sourceServer) {

    static DacpacConfig from(Map<String, Object> map, Path projectRoot) {
        return new DacpacConfig(
                projectRoot.resolve(Yamls.optionalString(map, "outputDir", "local-dev/mssql/dacpac")),
                Yamls.optionalString(map, "sourceServer", ""));
    }
}
