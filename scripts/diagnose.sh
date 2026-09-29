#!/usr/bin/env bash
# Diagnostico do FNAF Doom no Linux.
#
#   ./scripts/diagnose.sh                    (assume ~/Downloads/game)
#   ./scripts/diagnose.sh --dir /caminho/game
#
# Nao modifica nada. Serve para checar, antes ou depois de instalar:
#   - SO, driver Vulkan e se ha GPU de verdade
#   - Wine, prefixo e versao do GZDoom
#   - os dois bugs conhecidos (IWADSearch vazio, preset pesado)
#   - se o launcher esta instalado e o atalho valido

set -uo pipefail

GAMEDIR="$HOME/Downloads/game"
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/wineprefixes/fnafdoom"
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)   GAMEDIR="$2"; shift 2 ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "opcao desconhecida: $1" >&2; exit 2 ;;
    esac
done

ok=0; warn=0; bad=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; ok=$((ok+1)); }
warn() { printf '  \033[33maviso\033[0m %s\n' "$*"; warn=$((warn+1)); }
bad()  { printf '  \033[31mfalha\033[0m %s\n' "$*"; bad=$((bad+1)); }
head_() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

printf '\033[1mDiagnostico FNAF Doom\033[0m\n'

# ---------------------------------------------------------------- sistema
head_ "Sistema"
[ -r /etc/os-release ] && ok "$(. /etc/os-release && echo "$PRETTY_NAME")" || warn "nao foi ler /etc/os-release"
printf '       kernel: %s\n' "$(uname -r)"
printf '       arch:   %s\n' "$(uname -m)"

# ---------------------------------------------------------------- vulkan
head_ "Graficos / Vulkan"
if command -v vulkaninfo >/dev/null 2>&1; then
    dev=$(vulkaninfo --summary 2>/dev/null | grep -m1 'deviceName' | cut -d= -f2- | xargs)
    drv=$(vulkaninfo --summary 2>/dev/null | grep -m1 'driverName' | cut -d= -f2- | xargs)
    [ -n "$dev" ] && ok "device: ${dev:-?}" || bad "Vulkan nao reporta nenhum device"
    case "$drv" in
        radv|amdgpu|nouveau)
            ok "driver: $drv (GPU real)" ;;
        intel|anv)
            ok "driver: $drv (GPU real)" ;;
        lvp|lavapipe|llvmpipe|softpipe)
            warn "driver: $drv -> renderizacao POR SOFTWARE, espere poucos FPS" ;;
        "")
            warn "nao foi determinar o driver" ;;
        *) warn "driver desconhecido: $drv" ;;
    esac
else
    warn "vulkaninfo ausente (instale vulkan-tools) — sem isso nao da para checar a GPU"
fi

printf '       mesa:   %s\n' "$(glxinfo -B 2>/dev/null | grep -m1 'OpenGL renderer string' | cut -d: -f2- | xargs || echo '(glxinfo ausente)')"

# ---------------------------------------------------------------- wine
head_ "Wine"
if command -v wine >/dev/null 2>&1; then
    ok "wine: $(wine --version 2>/dev/null | xargs)"
else
    bad "wine nao instalado"
fi
[ -d "$PREFIX" ] && ok "prefixo: $PREFIX" || warn "prefixo ainda nao criado (rode o install.sh)"

# ---------------------------------------------------------------- jogo
head_ "Jogo em $GAMEDIR"
[ -d "$GAMEDIR" ] || { bad "diretorio do jogo nao existe"; GAMEDIR=""; }
if [ -n "$GAMEDIR" ]; then
    [ -f "$GAMEDIR/gzdoom.exe" ]  && ok "gzdoom.exe"        || bad "gzdoom.exe ausente"
    [ -f "$GAMEDIR/FNAFDoom.ipk3" ] && ok "FNAFDoom.ipk3 (IWAD)" || bad "FNAFDoom.ipk3 ausente — o jogo nao abre"
    [ -d "$GAMEDIR/wads/FD1" ]     && ok "wads/FD1"          || bad "wads/FD1 ausente — os WADs do mod nao estao ai"
    # FNAF.pk3 fica em wads/FD1/, nao na raiz do jogo.
    if ls "$GAMEDIR"/wads/FD1/FNAF*.pk3 >/dev/null 2>&1; then
        ok "$(ls "$GAMEDIR"/wads/FD1/FNAF*.pk3 2>/dev/null | wc -l | xargs) arquivo(s) FNAF*.pk3 em wads/FD1"
    else
        bad "FNAF.pk3 ausente em wads/FD1 — e onde estao os ~1 GB de recursos"
    fi
    ls "$GAMEDIR"/wads/Global/*.pk3 >/dev/null 2>&1 && ok "wads/Global/*.pk3" || warn "wads/Global/*.pk3 ausente"
    [ -f "$GAMEDIR/wads/FD1/install.dat" ] && ok "wads/FD1/install.dat" || warn "install.dat ausente — '--lowpoly' e '--fd N' nao vao funcionar"

    if [ -f "$GAMEDIR/gzdoom.exe" ]; then
        v=$(strings -a "$GAMEDIR/gzdoom.exe" 2>/dev/null | grep -m1 -oE 'g4\.[0-9]+')
        [ -n "$v" ] && ok "versao do GZDoom: $v"
    fi
fi

# ---------------------------------------------------------------- config
head_ "Configuracao"
CFG="$GAMEDIR/settings.ini"
if [ -f "$CFG" ]; then
    ok "settings.ini presente"
    [ -f "$GAMEDIR/settings.ini.orig" ] && ok "backup settings.ini.orig presente" \
        || warn "sem backup do config original (o install.sh cria)"

    # Bug 1: IWADSearch vazia
    if grep -qE '^\s*Path=\$PROGDIR\s*$' "$CFG" 2>/dev/null; then
        ok "IWADSearch.Directories = \$PROGDIR (bug do IWAD corrigido)"
    elif grep -qE '^\[IWADSearch\.Directories\]' "$CFG" 2>/dev/null; then
        bad "IWADSearch.Directories sem Path=\$PROGDIR -> 'Cannot find a game IWAD'"
    else
        warn "IWADSearch.Directories ausente (pode funcionar, mas o padrao nao esta garantido)"
    fi

    # Bug 2: preset pesado
    get() { grep -m1 -iE "^$1\s*=" "$CFG" 2>/dev/null | tail -1 | cut -d= -f2- | xargs; }
    w=$(get vid_scale_customwidth); h=$(get vid_scale_customheight)
    s=$(get vid_scalemode)
    if [ -n "$w" ] && [ -n "$h" ]; then
        if [ "$w" -ge 1600 ] 2>/dev/null; then
            warn "resolucao interna ${w}x${h} — pesado demais para GPU integrada (720p recomendado)"
        else
            ok "resolucao interna: ${w}x${h}"
        fi
    fi
    a=$(get gl_texture_filter_anisotropic)
    [ "$a" = "8" ] && warn "anisotropia 8x — costuma custar ~12% dos FPS; 4x e o equilibrio" || ok "anisotropia: ${a:-4}"
    m=$(get gl_multisample)
    [ "$m" = "2" ] && warn "MSAA 2x ligado — caro em iGPU" || ok "MSAA: ${m:-0}"
    ss=$(get gl_ssao)
    [ "$ss" = "1" ] && warn "SSAO ligado — o efeito mais caro do preset" || ok "SSAO: ${ss:-0}"
    b=$(get vid_preferbackend)
    [ "$b" = "2" ] && warn "vid_preferbackend=2 (OpenGL) — em Wayland, prefira Vulkan (1)" || ok "backend: ${b:-1} (Vulkan)"
    v=$(get vid_vsync)
    [ "$v" = "true" ] && warn "vsync ligado — abaixo de 60 FPS isso gera jitter" || ok "vsync: ${v:-false}"
    c=$(get cl_capfps)
    [ "$c" = "true" ] && warn "cl_capfps=true — derruba ~50 para ~35 FPS" || ok "cl_capfps: ${c:-false}"
    l=$(get language)
    ok "idioma: ${l:-en_US}"
else
    warn "settings.ini ausente — o install.sh cria um com o perfil recomendado"
fi

# ---------------------------------------------------------------- instalado
head_ "Launcher instalado"
command -v fnaf-doom >/dev/null 2>&1 && ok "fnaf-doom: $(command -v fnaf-doom)" \
    || warn "launcher nao instalado (rode o install.sh)"
D="$HOME/.local/share/applications/fnaf-doom.desktop"
[ -f "$D" ] && ok "atalho: $D" || warn "atalho ausente"
[ -f "$HOME/.local/share/icons/hicolor/256x256/apps/fnaf-doom.png" ] \
    && ok "icone instalado" || warn "icone ausente"
if command -v desktop-file-validate >/dev/null 2>&1 && [ -f "$D" ]; then
    desktop-file-validate "$D" >/dev/null 2>&1 && ok "atalho valido" || bad "atalho invalido"
fi

# ---------------------------------------------------------------- resumo
printf '\n\033[1mResumo:\033[0m %d ok, %d avisos, %d falhas\n' "$ok" "$warn" "$bad"
if [ "$bad" -gt 0 ]; then
    printf 'Ha falhas. See docs/01-diagnostico.md\n\n'; exit 1
fi
if [ "$warn" -gt 0 ]; then
    printf 'Nada quebrado, mas ha ajustes sugeridos acima.\n\n'
else
    printf 'Tudo certo. Rode:  fnaf-doom\n\n'
fi
