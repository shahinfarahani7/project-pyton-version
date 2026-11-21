# Worker APK build. The proxy address is not part of this image.
# The host Docker client injects its own proxy only while the build runs.
# Flutter 3.44.8 matches the machine that already builds this app. The base
# image supplies the Linux Android SDK; Flutter itself is replaced from the
# official archive because no published image tags that SDK yet.
ARG FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:3.29.3
FROM ${FLUTTER_IMAGE} AS build

USER root
ARG FLUTTER_VERSION=3.44.8
RUN rm -rf /sdks/flutter /opt/flutter \
    && curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && mkdir -p /opt \
    && tar -C /opt -xf /tmp/flutter.tar.xz \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics --android-sdk "${ANDROID_SDK_ROOT}"

COPY docker/apply-host-proxy.sh /opt/edgemint/apply-host-proxy.sh
COPY docker/build-apk.sh /opt/edgemint/build-apk.sh
RUN chmod +x /opt/edgemint/apply-host-proxy.sh /opt/edgemint/build-apk.sh

WORKDIR /src
COPY . /src

ARG EDGEMINT_WORKER_BASE_URL=http://172.20.34.71:8081
# Required when the API is behind a domain: without it the app uses the
# worker host on port 8080 for sign-in.
ARG EDGEMINT_API_BASE_URL=
ARG WORKER_MODEL_DOWNLOAD_SOURCE=
ARG WORKER_BUILD_NAME=
ARG WORKER_BUILD_NUMBER=
ENV EDGEMINT_WORKER_BASE_URL=${EDGEMINT_WORKER_BASE_URL} \
    EDGEMINT_API_BASE_URL=${EDGEMINT_API_BASE_URL} \
    WORKER_MODEL_DOWNLOAD_SOURCE=${WORKER_MODEL_DOWNLOAD_SOURCE} \
    WORKER_BUILD_NAME=${WORKER_BUILD_NAME} \
    WORKER_BUILD_NUMBER=${WORKER_BUILD_NUMBER} \
    PATH="/opt/flutter/bin:${PATH}"

RUN --mount=type=secret,id=android_debug_keystore,required=false \
    /opt/edgemint/build-apk.sh

FROM scratch AS export
COPY --from=build /out/app-release.apk /app-release.apk
