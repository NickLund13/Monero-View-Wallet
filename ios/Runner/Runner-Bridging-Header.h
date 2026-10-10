#import "GeneratedPluginRegistrant.h"

// The Tor Project's interface for running tor inside an app, as declared in
// tor's src/feature/api/tor_api.h. The library is tor.xcframework, which
// tool/fetch_tor.sh fetches; ios/Runner/InAppTor.swift calls these.
typedef struct tor_main_configuration_t tor_main_configuration_t;
tor_main_configuration_t *tor_main_configuration_new(void);
int tor_main_configuration_set_command_line(tor_main_configuration_t *cfg,
                                            int argc, char *argv[]);
void tor_main_configuration_free(tor_main_configuration_t *cfg);
int tor_run_main(const tor_main_configuration_t *cfg);
