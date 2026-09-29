#!/usr/bin/env bash
# install.sh — instala o launcher do FNAF Doom no Linux.
#
# O que faz:
#   1. cria um prefixo Wine dedicado (nao mexe no seu ~/.wine)
#   2. verifica se a Vulkan/RADV esta funcionando
#   3. corrige o settings.ini do jogo (veja docs/01-diagnostico.md)
#   4. instala o launcher, o atalho .desktop e o icone
#
# Uso:  ./install.sh [--dir PASTA_DO_JOGO] [--prefix PREFIXO_WINE]

set -euo pipefail

GAMEDIR="${FNAF_DOOM_DIR:-$HOME/Downloads/game}"
PREFIX="${FNAF_DOOM_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/wineprefixes/fnafdoom}"
BINDIR="$HOME/.local/bin"
APPDIR="$HOME/.local/share/applications"
ICONDIR="$HOME/.local/share/icons/hicolor/256x256/apps"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while (($#)); do
	case "$1" in
		--dir)    GAMEDIR="$2"; shift 2 ;;
		--prefix) PREFIX="$2"; shift 2 ;;
		-h|--help) sed -n '3,9p' "$0" | sed 's/^#\{1\} \{0,1\}//'; exit 0 ;;
		*) echo "opcao desconhecida: $1" >&2; exit 1 ;;
	esac
done

say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m  %s\n' "$*"; }
warn() { printf '  \033[33maviso\033[0m %s\n' "$*"; }
die()  { printf '\033[31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. pre-requisitos -------------------------------------------------------
say "Verificando pre-requisitos"
command -v wine >/dev/null || die "wine nao encontrado (Instale: sudo pacman -S wine / sudo apt install wine)"
ok "wine: $(wine --version)"
[[ -f $GAMEDIR/gzdoom.exe ]] || die "gzdoom.exe nao encontrado em $GAMEDIR (use --dir)"
ok "jogo em $GAMEDIR"

# --- 2. prefixo Wine dedicado ------------------------------------------------
say "Preparando prefixo Wine dedicado"
if [[ -f $PREFIX/system.reg ]]; then
	ok "prefixo ja existe: $PREFIX"
else
	mkdir -p "$PREFIX"
	[[ -d $GAMEDIR ]] || die "pasta do jogo nao encontrada: $GAMEDIR"
	say "criando prefixo win64 (pode levar ~1 min)"
	WINEARCH=win64 WINEPREFIX="$PREFIX" wineboot -u >/dev/null 2>&1 || true
	[[ -f $PREFIX/system.reg ]] || die "falha ao criar o prefixo em $PREFIX"
	ok "prefixo criado"
fi
# nota: o FNAF Doom nao precisa de vcrun/dxvk. O Wine 9+ ja traz o loader
# Vulkan embutido e o proprio gzdoom.exe linka o CRT estaticamente.

# --- 3. Vulkan ---------------------------------------------------------------
say "Verificando Vulkan"
if command -v vulkaninfo >/dev/null && vulkaninfo --summary 2>/dev/null | grep -q 'deviceName'; then
	vulkaninfo --summary 2>/dev/null | awk -F'= *' '/deviceName|driverName/ {gsub(/^[ \t]+/,"",$2); printf "  %s\n", $2}' | head -2 | sed 's/^/  /'
	ok "Vulkan disponivel"
else
	warn "vulkaninfo nao reportou nenhum device. O jogo ainda roda em OpenGL (--opengl)."
fi

# --- 4. settings.ini ---------------------------------------------------------
INI="$GAMEDIR/settings.ini"
say "Ajustando $INI"

[[ -f $INI ]] || die "settings.ini nao encontrado em $GAMEDIR"
[[ -f $INI.orig ]] || { cp "$INI" "$INI.orig"; ok "backup criado: settings.ini.orig"; }

# Substitui chave=valor em qualquer secao do .ini; se a chave nao existir,
# insere logo depois do cabecalho [GlobalSettings].
set_cvar() {
	local key="$1" val="$2"
	if grep -qE "^[[:space:]]*${key}=" "$INI"; then
		sed -i -E "s|^([[:space:]]*)${key}=.*|\1${key}=${val}|" "$INI"
	elif grep -qE '^\[GlobalSettings\][[:space:]]*$' "$INI"; then
		awk -v k="$key" -v v="$val" '
			/^\[GlobalSettings\][[:space:]]*$/ && !ins { print; print k "=" v; ins=1; next }
			{ print }' "$INI" > "$INI.tmp" && mv "$INI.tmp" "$INI"
	else
		printf '\n[GlobalSettings]\n%s=%s\n' "$key" "$val" >> "$INI"
	fi
}

# O bug critico: [IWADSearch.Directories] vazia SUBSTITUI os diretorios padrao do
# GZDoom e faz ele nao encontrar o IWAD -> "Cannot find a game IWAD".
if ! grep -A5 '^\[IWADSearch.Directories\]' "$INI" | grep -q 'Path='; then
	awk '
		/^\[IWADSearch\.Directories\]/ && !ins { print; print "Path=$PROGDIR"; ins=1; next }
		{ print }
	' "$INI" > "$INI.tmp" && mv "$INI.tmp" "$INI"
	ok "corrigido: [IWADSearch.Directories] Path=\$PROGDIR"
else
	ok "[IWADSearch.Directories] ja estava correto"
fi

# Perfil de performance medido em iGPU AMD Vega 8 (veja docs/02-performance.md).
# Ajuste os valores conforme o seu hardware.
set_cvar vid_preferbackend          1        # 1 = Vulkan, 2 = OpenGL
set_cvar vid_fullscreen             true
set_cvar vid_maxfps                 60
set_cvar vid_vsync                  false    # vsync com FPS < 60 gera jitter
set_cvar cl_capfps                  false    # true derruba para ~35 fps no GZDoom 4.11
set_cvar vid_scalemode              5        # 5 = resolucao custom
set_cvar vid_scale_customwidth      1280
set_cvar vid_scale_customheight     720
set_cvar gl_multisample             0        # 2x MSAA e caro em iGPU
set_cvar gl_fxaa                    1
set_cvar gl_ssao                    0        # o custo mais alto do preset
set_cvar gl_texture_filter_anisotropic 4     # 8 derruba ~15% de FPS
set_cvar gl_plane_reflection        false
set_cvar gl_light_shadowmap         true
set_cvar gl_shadowmap_quality       512
set_cvar gl_bloom                   true
set_cvar language                   ptb
ok "perfil de video aplicado"

# --- 5. launcher, atalho e icone ---------------------------------------------
say "Instalando launcher"
mkdir -p "$BINDIR" "$APPDIR" "$ICONDIR"
install -Dm755 "$HERE/fnaf-doom" "$BINDIR/fnaf-doom"
ok "launcher: $BINDIR/fnaf-doom"

sed -e "s|^Exec=.*|Exec=$BINDIR/fnaf-doom|" \
    "$HERE/../desktop/fnaf-doom.desktop.in" > "$APPDIR/fnaf-doom.desktop"
chmod +x "$APPDIR/fnaf-doom.desktop"
command -v desktop-file-validate >/dev/null && desktop-file-validate "$APPDIR/fnaf-doom.desktop" && ok "atalho validado: $APPDIR/fnaf-doom.desktop"

if [[ -f $HERE/../desktop/fnaf-doom.png ]]; then
	install -Dm644 "$HERE/../desktop/fnaf-doom.png" "$ICONDIR/fnaf-doom.png"
	command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
	ok "icone instalado"
else
	ok "icone: rode scripts/make-icon.py para gerar"
fi

case ":$PATH:" in
	*":$BINDIR:"*) ;;
	*) warn "$BINDIR nao esta no seu PATH. Adicione: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

cat <<EOF

$(say "Instalado. Para jogar:")

  fnaf-doom

  (ou procure "FNAF Doom" no menu de aplicacoes)

Opcoes uteis:
  fnaf-doom --res 1600x900    mais nitido, ~36 fps
  fnaf-doom --ssao on         melhor visual, ~44 fps em 720p
  fnaf-doom --mangohud        ver FPS na tela
  fnaf-doom --dry-run         mostra o comando sem abrir o jogo

Para voltar ao config original:  cp "$INI.orig" "$INI"
EOF
