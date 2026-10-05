#!/bin/bash
set -u
dest=${TMUX_BUILDS:-${TMPDIR:-/tmp}/tmux-builds}
versions=("$@")
[ ${#versions[@]} -eq 0 ] && versions=(3.1c 3.2a 3.3a 3.4 3.5a 3.6b 3.7c git:release_3.7d git:release_3.8 git:master)
mkdir -p "$dest" && cd "$dest" || exit 1

if command -v brew >/dev/null; then
  for formula in libevent ncurses utf8proc; do
    prefix=$(brew --prefix "$formula")
    export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    export CPPFLAGS="-I$prefix/include ${CPPFLAGS:-}"
    export LDFLAGS="-L$prefix/lib ${LDFLAGS:-}"
  done
  export PATH="$(brew --prefix bison)/bin:$PATH"
fi
export CFLAGS="-O2 -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types"

for version in "${versions[@]}"; do
  name=${version#git:}
  rm -rf "src-$name" "$name"
  if [[ $version == git:* ]]; then
    git clone -q -c advice.detachedHead=false --depth 1 --branch "$name" https://github.com/tmux/tmux.git "src-$name" &&
      (cd "src-$name" && sh autogen.sh >/dev/null 2>&1) || { echo "FAIL fetch $name"; continue; }
  else
    mkdir "src-$name" &&
      curl -fsSL "https://github.com/tmux/tmux/releases/download/$version/tmux-$version.tar.gz" |
      tar xz -C "src-$name" --strip-components 1 || { echo "FAIL fetch $name"; continue; }
  fi
  if (cd "src-$name" && ./configure --prefix="$dest/$name" --enable-utf8proc && make -j8 && make install) >"build-$name.log" 2>&1; then
    echo "OK $name: $("$dest/$name/bin/tmux" -V)"
  else
    echo "FAIL build $name (see $dest/build-$name.log)"
  fi
done
