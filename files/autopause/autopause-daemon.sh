#!/bin/bash

. /autopause/autopause-fcns.sh

. /start-utils

logAutopause "Starting knockd"
sudo /usr/sbin/knockd -c /tmp/knockd-config.cfg -d -v -D
logAutopause "Started!"
if [ $? -ne 0 ] ; then
  while :
  do
    if [[ -n $(ps -o comm | grep java) ]] ; then
      break
    fi
    sleep 0.1
  done
  logAutopause "Failed to start knockd daemon."
  logAutopause "Possible cause: docker's host network mode."
  logAutopause "Recreate without host mode or disable autopause functionality."
  logAutopause "Stopping server."
  killall -SIGTERM java
  exit 1
fi

logAutopause "Entering loop"
STATE=INIT

while :
do
  logAutopause "Next iteration, current state $STATE"
  case X$STATE in
  XINIT)
    # Server startup
    if mc_server_listening ; then
      TIME_THRESH=$(($(current_uptime)+$AUTOPAUSE_TIMEOUT_INIT))
      logAutopause "MC Server listening for connections - stopping in $AUTOPAUSE_TIMEOUT_INIT seconds"
      STATE=K
    fi
    ;;
  XK)
    # Knocked
    if java_clients_connected ; then
      logAutopause "Client connected - waiting for disconnect"
      STATE=E
    else
      if [[ $(current_uptime) -ge $TIME_THRESH ]] ; then
        logAutopause "No client connected since startup / knocked - stopping"
        /autopause/pause.sh
        STATE=S
      fi
    fi
    ;;
  XE)
    # Established
    if ! java_clients_connected ; then
      TIME_THRESH=$(($(current_uptime)+$AUTOPAUSE_TIMEOUT_EST))
      logAutopause "All clients disconnected - stopping in $AUTOPAUSE_TIMEOUT_EST seconds"
      STATE=I
    fi
    ;;
  XI)
    # Idle
    if java_clients_connected ; then
      logAutopause "Client reconnected - waiting for disconnect"
      STATE=E
    else
      if [[ $(current_uptime) -ge $TIME_THRESH ]] ; then
        logAutopause "No client reconnected - stopping"
        /autopause/pause.sh
        STATE=S
      fi
    fi
    ;;
  XS)
    # Stopped
    if rcon_client_exists ; then
      /autopause/resume.sh
    fi
    if java_running ; then
      if java_clients_connected ; then
        logAutopause "Client connected - waiting for disconnect"
        STATE=E
      else
        TIME_THRESH=$(($(current_uptime)+$AUTOPAUSE_TIMEOUT_KN))
        logAutopause "Server was knocked - waiting for clients or timeout"
        STATE=K
      fi
    fi
    ;;
  *)
    logAutopause "Error: invalid state: $STATE"
    ;;
  esac
  if [[ "$STATE" == "S" ]] ; then
    # before rcon times out
    sleep 2
  else
    sleep $AUTOPAUSE_PERIOD
  fi
done
