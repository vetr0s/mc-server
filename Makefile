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

.PHONY: help preflight jar mods client-mods eula settings run start stop console logs status clean clean-all

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

status:
	@echo "tailnet:  $${BIND_IP:-(down)}  [$$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"')]"
	@printf "session:  "; tmux has-session -t $(SESSION) 2>/dev/null && echo "running" || echo "stopped"
	@printf "listener: "; l=$$(lsof -nP -iTCP:$(PORT) -sTCP:LISTEN 2>/dev/null | tail -1); echo "$${l:-none}"
	@printf "sleep:    "; if pmset -g 2>/dev/null | grep -qi "sleepdisabled *1" || \
	  plutil -p /Library/Preferences/com.apple.PowerManagement.plist 2>/dev/null | grep -qi '"SleepDisabled" => 1'; \
	then echo "lid-close sleep disabled"; \
	else echo "WILL SLEEP on lid close -> sudo pmset -a disablesleep 1"; fi

clean:
	@rm -rf $(SERVER)/mods client/mods/*.jar $(JAR)
	@echo "Removed mods and launcher."

clean-all: clean
	@rm -rf $(SERVER)/world* $(SERVER)/logs $(SERVER)/server.properties $(SERVER)/eula.txt $(SERVER)/.fabric $(SERVER)/libraries $(SERVER)/versions
	@echo "Removed worlds and generated config."
