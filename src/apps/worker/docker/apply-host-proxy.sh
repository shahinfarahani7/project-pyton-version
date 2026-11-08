#!/bin/sh
# The proxy address is never stored in this file. Docker on the host injects
# HTTP(S)_PROXY for the build. This only teaches Gradle, which ignores those
# variables, and the build removes the temporary file before the layer is saved.
apply_host_proxy() {
  proxy="${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}}"
  if [ -z "$proxy" ]; then
    echo "No host proxy was injected. Downloads will go directly."
    return 0
  fi
  rest=${proxy#*://}
  rest=${rest%%/*}
  hostport=$rest
  case "$rest" in
    *@*) hostport=${rest#*@} ;;
  esac
  host=${hostport%%:*}
  port=${hostport##*:}
  if [ "$port" = "$host" ]; then
    port=80
  fi
  noproxy="${no_proxy:-${NO_PROXY:-localhost,127.0.0.1}}"
  noproxy=$(printf '%s' "$noproxy" | tr ',' '|')
  mkdir -p "${HOME}/.gradle"
  umask 077
  cat > "${HOME}/.gradle/gradle.properties" <<EOF
systemProp.http.proxyHost=${host}
systemProp.http.proxyPort=${port}
systemProp.https.proxyHost=${host}
systemProp.https.proxyPort=${port}
systemProp.http.nonProxyHosts=${noproxy}
org.gradle.daemon=false
EOF
  echo "Gradle is using the proxy injected by the host."
}
