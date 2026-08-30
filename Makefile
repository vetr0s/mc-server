include config.mk

# The tailnet address is resolved, not pinned. Override BIND_IP in config.mk
# only if you deliberately want the server reachable off the tailnet.
ifeq ($(strip $(BIND_IP)),)
BIND_IP := $(shell tailscale ip -4 2>/dev/null | head -1)
endif

SERVER   := server
JAR      := $(SERVER)/fabric-server-launch.jar
JAR_URL  := https://meta.fabricmc.net/v2/versions/loader/$(MC_VERSION)/$(FABRIC_LOADER)/$(FABRIC_INSTALLER)/server/jar
SESSION  := mc-server
JAVA_CMD := java -Xms$(MEMORY) -Xmx$(MEMORY) -jar fabric-server-launch.jar nogui

export MC_VERSION BIND_IP PORT

.PHONY: help preflight jar mods backup regen-world install-service uninstall-service client-mods eula settings run start stop console logs status clean clean-all

help:
	@echo "mc-server: Fabric $(MC_VERSION) on the tailnet"
	@echo ""
	@echo "  make jar          Download the Fabric server launcher"
	@echo "  make mods         Sync server/mods to mods.txt"
	@echo "  make client-mods  Sync client/mods to client-mods.txt (hand these to players)"
	@echo "  make eula         Accept the Minecraft EULA (https://aka.ms/MinecraftEULA)"
	@echo "  make settings     Merge server-settings.properties into server.properties"
	@echo ""
	@echo "  make run          Run in the foreground (ctrl-c stops it)"
	@echo "  make start        Run detached in tmux, survives a closed lid"
	@echo "  make console      Attach to the running console (ctrl-b d to detach)"
	@echo "  make stop         Save and shut down cleanly"
	@echo "  make logs         Tail the server log"
	@echo "  make backup       Snapshot the world to backups/, keeps the last 10"
	@echo "  make regen-world SEED=<seed>  Back up, wipe, and reseed the world"
	@echo ""
	@echo "  make install-service    Start the server automatically at login"
	@echo "  make uninstall-service  Stop doing that"
	@echo "  make status       Tailnet address, listener, session state"
	@echo ""
	@echo "  make clean        Remove mods and the launcher"
	@echo "  make clean-all    Also remove worlds and generated config"

$(JAR):
	@echo "Fetching Fabric $(FABRIC_LOADER) launcher for $(MC_VERSION)..."
	@mkdir -p $(SERVER)
	@curl -sfL -o $(JAR) "$(JAR_URL)" || { echo "No Fabric build for $(MC_VERSION)/$(FABRIC_LOADER)"; exit 1; }

jar: $(JAR)

mods:
	@echo "Server mods ($(MC_VERSION)):"
	@./bin/fetch-mods.sh mods.txt $(SERVER)/mods

client-mods:
	@echo "Client mods ($(MC_VERSION)):"
	@./bin/fetch-mods.sh client-mods.txt client/mods

eula:
	@mkdir -p $(SERVER)
	@echo "eula=true" > $(SERVER)/eula.txt
	@echo "EULA accepted. Terms: https://aka.ms/MinecraftEULA"

settings:
	@./bin/inject-settings.sh server-settings.properties $(SERVER)/server.properties

# Everything the server needs before it can bind. Fails loudly if the tailnet
# is down, because a tailnet-only server with no tailnet has nowhere to listen.
preflight: $(JAR) mods
	@test -n "$(BIND_IP)" || { echo "No tailscale IPv4. Start Tailscale, then retry."; exit 1; }
	@test -f $(SERVER)/eula.txt || { echo "Run 'make eula' first."; exit 1; }
	@$(MAKE) -s settings

run: preflight
	@cd $(SERVER) && $(JAVA_CMD)

start: preflight
	@tmux has-session -t $(SESSION) 2>/dev/null && { echo "Already running. 'make console' to attach."; exit 1; } || true
	@cd $(SERVER) && tmux new-session -d -s $(SESSION) '$(JAVA_CMD)'
	@echo "Started in tmux session '$(SESSION)'. Players connect to $(BIND_IP):$(PORT)"

console:
	@tmux attach -t $(SESSION)

stop:
	@tmux has-session -t $(SESSION) 2>/dev/null || { echo "Not running."; exit 0; }
	@tmux send-keys -t $(SESSION) stop Enter
	@echo "Sent 'stop'. Waiting for the world to save..."
	@while tmux has-session -t $(SESSION) 2>/dev/null; do sleep 1; done
	@echo "Stopped."

logs:
	@tail -f $(SERVER)/logs/latest.log

# Safe to run while players are online; writes are held only for the tar.
backup:
	@./bin/backup.sh $(SERVER) backups $(SESSION)

# Change the world seed without losing the old world. Backs it up, deletes it,
# and writes level-seed so the next start generates fresh terrain. Refuses
# while the server is up, because deleting the world under it corrupts the save.
regen-world:
	@test -n "$(SEED)" || { echo "Usage: make regen-world SEED=<seed>"; exit 1; }
	@tmux has-session -t $(SESSION) 2>/dev/null && { echo "Server is running. Run 'make stop' first."; exit 1; } || true
	@$(MAKE) -s backup
	@rm -rf $(SERVER)/world*
	@touch $(SERVER)/server.properties
	@awk -F= -v k=level-seed -v v='$(SEED)' 'BEGIN{OFS=FS} $$1==k{print k"="v;s=1;next}{print} END{if(!s)print k"="v}' \
	  $(SERVER)/server.properties > $(SERVER)/server.properties.tmp && mv $(SERVER)/server.properties.tmp $(SERVER)/server.properties
	@echo "World cleared, seed set to $(SEED). Run 'make start' to generate it."

LABEL := com.$(USER).mc-server
PLIST := $(HOME)/Library/LaunchAgents/$(LABEL).plist

# A LaunchAgent, not a LaunchDaemon. The Tailscale app is per-user, so there is
# no tunnel to bind to until someone logs in.
install-service:
	@mkdir -p $(HOME)/Library/LaunchAgents $(SERVER)/logs
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>Label</key><string>$(LABEL)</string>' \
	  '  <key>ProgramArguments</key><array>' \
	  '    <string>/bin/bash</string>' \
	  '    <string>$(CURDIR)/bin/boot-start.sh</string>' \
	  '    <string>$(CURDIR)</string>' \
	  '  </array>' \
	  '  <key>RunAtLoad</key><true/>' \
	  '  <key>WorkingDirectory</key><string>$(CURDIR)</string>' \
	  '  <key>StandardOutPath</key><string>$(CURDIR)/$(SERVER)/logs/launchd.log</string>' \
	  '  <key>StandardErrorPath</key><string>$(CURDIR)/$(SERVER)/logs/launchd.log</string>' \
	  '</dict></plist>' > $(PLIST)
	@plutil -lint $(PLIST) >/dev/null || { echo "generated plist is malformed"; exit 1; }
	@launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) $(PLIST)
	@echo "Installed $(LABEL). Starts at login, logs to $(SERVER)/logs/launchd.log"

uninstall-service:
	@launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null || true
	@rm -f $(PLIST)
	@echo "Removed $(LABEL). The server no longer starts at login."

status:
	@echo "tailnet:  $${BIND_IP:-(down)}  [$$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"')]"
	@printf "session:  "; tmux has-session -t $(SESSION) 2>/dev/null && echo "running" || echo "stopped"
	@printf "listener: "; l=$$(lsof -nP -iTCP:$(PORT) -sTCP:LISTEN 2>/dev/null | tail -1); echo "$${l:-none}"
	@printf "sleep:    "; if pmset -g 2>/dev/null | grep -qiE "sleepdisabled[[:space:]]+1" || \
	  plutil -p /Library/Preferences/com.apple.PowerManagement.plist 2>/dev/null | grep -qi '"SleepDisabled" => \(1\|true\)'; \
	then echo "lid-close sleep disabled"; \
	else echo "WILL SLEEP on lid close -> sudo pmset -a disablesleep 1"; fi

clean:
	@rm -rf $(SERVER)/mods client/mods/*.jar $(JAR)
	@echo "Removed mods and launcher."

clean-all: clean
	@rm -rf $(SERVER)/world* $(SERVER)/logs $(SERVER)/server.properties $(SERVER)/eula.txt $(SERVER)/.fabric $(SERVER)/libraries $(SERVER)/versions
	@echo "Removed worlds and generated config."
