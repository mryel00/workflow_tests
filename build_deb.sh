#!/usr/bin/env bash

# Usage: ./build_deb.sh <version>
VERSION="${1}"
PKGNAME="spyglass"

DEPENDS=(python3-libcamera python3-kms++ python3-picamera2 python3-av)

TMP_VENV="/opt/${PKGNAME}/venv"
STAGING_DIR="$(mktemp -d /tmp/${PKGNAME}-pkg.XXXXXX)"
VENV_DIR="${STAGING_DIR}/opt/${PKGNAME}/venv"
BIN_DIR="${STAGING_DIR}/usr/bin"
EXTERNAL_REPO="https://github.com/mryel00/spyglass"

echo "Creating virtualenv in ${TMP_VENV}"
python3 -m venv --system-site-packages "${TMP_VENV}"

"${TMP_VENV}/bin/pip" install --upgrade pip setuptools wheel

# If EXTERNAL_REPO is provided in the environment, install it into the venv so it's included in the packaged venv.
echo "Installing external repository into venv from: ${EXTERNAL_REPO}"
TMP_EXT="$(mktemp -d /tmp/${PKGNAME}-ext.XXXXXX)"
git clone --depth=1 -b apt "${EXTERNAL_REPO}" "${TMP_EXT}"
"${TMP_VENV}/bin/pip" install --no-cache-dir "${TMP_EXT}"
echo "Installing requirements into venv"
"${TMP_VENV}/bin/pip" install --no-cache-dir -r "${TMP_EXT}/requirements.txt"
rm -rf "${TMP_EXT}"

echo "Cleaning up virtualenv to reduce size"
"${TMP_VENV}/bin/pip" cache purge
find "${TMP_VENV}" -name '__pycache__' -type d -print0 | xargs -0 -r rm -rf
find "${TMP_VENV}" -name '*.pyc' -print0 | xargs -0 -r rm -f
rm -rf "${TMP_VENV}/.cache" "${TMP_VENV}/pip-selfcheck.json" "${TMP_VENV}/share"

echo "Removing pip/wheel from staged venv to reduce size"
PYVER="$(${TMP_VENV}/bin/python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
STAGED_SITEPKG="${TMP_VENV}/lib/python${PYVER}/site-packages"
rm -f "${TMP_VENV}/bin/pip" "${TMP_VENV}/bin/pip3"
rm -rf "${STAGED_SITEPKG}/pip" "${STAGED_SITEPKG}/pip-*" "${STAGED_SITEPKG}/pip-*dist-info"
rm -rf "${STAGED_SITEPKG}/wheel" "${STAGED_SITEPKG}/wheel-*" "${STAGED_SITEPKG}/wheel-*dist-info"
rm -rf "${STAGED_SITEPKG}/setuptools" "${STAGED_SITEPKG}/setuptools-*" "${STAGED_SITEPKG}/setuptools-*dist-info"

echo "Preparing staging layout at ${STAGING_DIR}"
mkdir -p "${VENV_DIR}" "${BIN_DIR}"

echo "Copying virtualenv to staging"
cp -a "${TMP_VENV}/." "${VENV_DIR}/"

# Fix permissions in the staged venv so non-root users can run it:
# - directories: 0755 (owner rwx, group/other rx)
# - files: 0644 (owner rw, group/other r)
# - venv/bin/* executables: 0755
echo "Adjusting permissions in staged venv so non-root users can execute it"
# give directories execute bit so they are traversable
find "${VENV_DIR}" -type d -exec chmod 0755 {} +
# make regular files readable
find "${VENV_DIR}" -type f -exec chmod 0644 {} +
# make sure scripts and binaries in bin are executable
if [ -d "${VENV_DIR}/bin" ]; then
  find "${VENV_DIR}/bin" -type f -exec chmod 0755 {} +
fi
# ensure any existing shebang scripts under bin are executable (some tools create them)
if [ -d "${VENV_DIR}/bin" ]; then
  chmod -R a+rx "${VENV_DIR}/bin" || true
fi

echo "Writing wrapper to ${BIN_DIR}/${PKGNAME}"
cat > "${BIN_DIR}/${PKGNAME}" <<'EOF'
#!/usr/bin/env bash

APP_BIN="/opt/spyglass/venv/bin/spyglass"

exec "${APP_BIN}" "$@"
EOF
chmod 0755 "${BIN_DIR}/${PKGNAME}"

FPM_DEPENDS=()
for dep in "${DEPENDS[@]}"; do
  FPM_DEPENDS+=(--depends "${dep}")
done

echo "Building .deb with fpm (declaring system package dependencies: ${DEPENDS[*]:-none})"
# Ensure fpm is installed: sudo gem install --no-document fpm
fpm -s dir -t deb \
  -n "${PKGNAME}" -v "${VERSION}" \
  --description "MyApp packaged with a bundled virtualenv and pip-installed app" \
  --maintainer "Your Name <you@example.com>" \
  --url "https://github.com/mryel00/spyglass" \
  --license "GPLv3" \
  "${FPM_DEPENDS[@]}" \
  -C "${STAGING_DIR}" .

echo "Cleaning up"
rm -rf "${TMP_VENV}" "${STAGING_DIR}"
echo "Done. .deb is in the current directory."
