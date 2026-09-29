# 01 — Diagnóstico

Como foi discovered *o que* estava quebrado e *por que*, sem acesso ao
código-fonte do launcher original.

---

## 1. Reconhecimento do binário

Antes de tentar qualquer coisa, vale saber o que realmente existe na pasta:

```bash
ls -la ~/Downloads/game
file ~/Downloads/game/gzdoom.exe
```

```
gzdoom.exe: PE32+ executable for MS Windows 6.00 (GUI), x86-64, 14 sections
```

`PE32+` confirma: binário Windows de 64 bits. O Wine precisa de um prefixo
`win64` (e não 32 bits) para rodá-lo.

### Dependências de DLL

```bash
objdump -x gzdoom.exe | grep -iE '\.dll' | sort -u
```

```
ADVAPI32.dll  COMCTL32.dll  COMDLG32.dll  dbghelp.dll  DINPUT8.dll
GDI32.dll  KERNEL32.dll  ole32.dll  PSAPI.DLL  SHELL32.dll
USER32.dll  WINMM.dll  WSOCK32.dll  zmusic.dll
```

Só `dlls` do sistema (todas nativas do Wine) mais a `zmusic.dll`, que já vem
na pasta. **Nenhuma redistribuível do MSVC é necessária** — o GZDoom linka o CRT
estaticamente. Isso elimina de cara o `winetricks vcrun2022`, que muita gente
instalaria à toa.

---

## 2. O launcher é Windows e não tem equivalente

`FDLauncher.exe` é `PE32` (32 bits), um app Qt. Duas saídas:

- rodá-lo pelo Wine e deixar que ele chame o `gzdoom.exe` — funciona, mas
  adiciona uma camada de janela e um download de 13 MB que só existe para
  montar uma linha de comando;
- reconstruir a lógica em shell.

A segunda foi escolhida. Para isso, era preciso saber **quais** argumentos ele
usa.

### 2.1 Primeira passada: o que existe

```bash
strings -n 4 FDLauncher.exe | grep -Ei 'gzdoom|-iwad|-file|FNAF|install.dat'
```

```
FNAF 1
FNAF 2
FNAF 3
FNAF 4
-file
-iwad
/game/FNAFDoom.ipk3
/game/gzdoom.exe
```

Já aparece a informação mais importante: **o IWAD é `FNAFDoom.ipk3`**, não
`gzdoom.pk3` (esse é carregado sozinho por estar ao lado do executável).
Também que o launcher gerencia os quatro jogos da franquia.

### 2.2 Segunda passada: offsets revelam a ordem

O truque é `strings -t d`, que imprime o **offset decimal** de cada string. Como
o launcher concatena os argumentos na ordem em que os guardou, a sequência de
offsets é a sequência de uso:

```bash
strings -n 2 -t d FDLauncher.exe | awk '{o=$1+0} o>=6331050 && o<=6331420'
```

```
6331076 /game/wads/FD
6331092 /install.dat
6331116 version=
6331128 files=
6331140 |MATERIALS
6331152 |LOWPOLY
6331164 -file
6331172 /game/wads/Global/*
6331192 -iwad
6331200 /game/FNAFDoom.ipk3
6331220 -skill
6331232 -config
6331240 -host
6331248 -map
6331256 +map
6331264 -netmode
6331276 -port
6331284 -join
6331292 +sv_cheats
6331304 /game/gzdoom.exe
```

Leitura do bloco:

- `install.dat` é lido, e o launcher procura as chaves `version=` e `files=`;
- existem duas flags condicionais: `|MATERIALS` e `|LOWPOLY`;
- o comando é `gzdoom.exe ... -file <wads> -iwad <iwad>`;
- os wads globales entram como `wads/Global/*`;
- `-skill`, `-host`, `-map`, `-netmode`, `-port`, `-join`, `+sv_cheats` são
  opções de rede/multiplayer (o `+sv_cheats` aparece sem prefixo `-` porque o
  `+` inicial é sintaxe de console do GZDoom, não switch).

### 2.3 O `install.dat` é a fonte de verdade

```
$ cat wads/FD1/install.dat
version=4.1.1
files=
[
	FNAF.wad,
	FNAF.pk3,
	FNAF_LowPoly.pk3|LOWPOLY,
]
```

O formato é autoexplicativo: nome do arquivo, vírgula, e opcionalmente `|FLAG`
para arquivos opcionais. É o mesmo formato para os FNAF 2, 3 e 4 — por isso o
shell lê o arquivo em vez de hardcodar nomes, e `--fd N` funciona para todos.

### 2.4 O `.ipk3` é um zip (IWAD)

```bash
unzip -l FNAFDoom.ipk3 | head
unzip -p FNAFDoom.ipk3 iwadinfo.txt
```

```
IWad
{
	Name = "FNaF Doom"
	AutoName = "FNAFDoom"
	Game = "Doom"
	Config = "FNAFDoom"
	MapInfo = "mapinfo/doom1.txt"
}
```

Sem o campo `IWadInfo` de um IWAD clássico, o GZDoom precisa de `-iwad`
explícito. E `Config = "FNAFDoom"` explica a seção
`[FNAFDoom.ConsoleVariables]` no `settings.ini` — é ali que o mod guarda os
próprios CVars, separada do `[GlobalSettings]`.

---

## 3. O bug do IWAD

### 3.1 O sintoma

Rodando direto, sem `-config`:

```bash
wine gzdoom.exe -iwad FNAFDoom.ipk3 -file wads/FD1/FNAF.wad wads/FD1/FNAF.pk3 wads/Global/JF.pk3
```

funcionava. Bastou acrescentar `-config settings.ini` — que é o certo, para o
jogo respeitar o preset — e o jogo passou a abortar:

```
**** DIED WITH FATAL ERROR:
Cannot find a game IWAD (doom.wad, doom2.wad, heretic.wad, etc.).
Did you install GZDoom properly? You can do either of the following:

1. Place one or more of these wads in the same directory as GZDoom.
2. Edit your gzdoom-username.ini and add the directories of your iwads
to the list beneath [IWADSearch.Directories]
```

### 3.2 A causa

O `settings.ini` original tem:

```ini
[IWADSearch.Directories]

[FileSearch.Directories]
```

A seção existe mas está **vazia**. No GZDoom, essa seção define a lista de
diretórios de busca de IWAD; quando presente, ela *substitui* a lista padrão
(programdir, `%APPDATA%`, `/usr/share/games/doom`...). Vazia, sobra zero
caminho.

O detalhe que confunde: **`-iwad FNAFDoom.ipk3` continua na linha de comando**,
então por que falha? Porque o GZDoom só trata um `-iwad` como caminho direto
quando ele **contém separador de diretório**. Sem barra, ele trata como um
*nome a ser procurado* — e a busca está vazia. Daí a mensagem de "não achou o
IWAD" mesmo com o arquivo a dois centímetros.

Confirmação experimental: o log do primeiro teste bem-sucedido mostra o IWAD
carregado com prefixo `./`, sinal de que veio de uma busca no progdir, e não
de um caminho absoluto:

```
adding ./FNAFDoom.ipk3, 93 lumps
```

### 3.3 A correção

```ini
[IWADSearch.Directories]
Path=$PROGDIR
```

`$PROGDIR` é uma variável do próprio GZDoom que aponta para a pasta do
executável — assim o launcher funciona de onde o jogo estiver, sem caminho
absoluto no meio.

---

## 4. Descobrindo os CVars

Para ajustar performance sem documentação, os nomes dos CVars foram extraídos
do próprio executável. Todo CVar é registrado com seu nome como string literal:

```bash
strings -n 4 gzdoom.exe | grep -E '^(r_|gl_|vid_|cl_|v_)[a-z0-9_]+$' | sort -u
```

 Saiu uma lista de 208 CVars. Filtrando os relevantes:

```bash
strings -n 4 gzdoom.exe | grep -E '^(r_|gl_|vid_|cl_|v_)[a-z0-9_]+$' \
  | grep -E 'bloom|ssao|shadow|multisample|fxaa|scale|maxfps|vsync|capfps'
```

```
cl_capfps
gl_bloom_amount
gl_fxaa
gl_multisample
gl_precache
gl_shadowmap_filter
gl_shadowmap_quality
gl_ssao
gl_ssao_bias / gl_ssao_blur / gl_ssao_exponent / gl_ssao_portals
gl_ssao_radius / gl_ssao_strength
gl_texture_filter_anisotropic
r_dynlights
vid_maxfps
vid_scale_customheight / vid_scale_customwidth
vid_scalefactor / vid_scalemode / vid_setscale
vid_vsync
```

### Surpresa: o prefixo

Esperava `r_ssao` e `r_bloom` (o GZDoom 4.10 havia renomeado os CVars de GL
para genéricos). Neste build **4.11.1 não existem** — `grep '^r_'` só devolve
outros nomes, e os de efeito continuam `gl_*`. Vale checar a versão antes de
assumir:

```bash
strings gzdoom.exe | grep -m1 -E 'GZDoom version|^g4\.'
```

### `gl_bloom` não existe como toggle

O `settings.ini` do mod tem `gl_bloom=true`, mas esse nome não aparece na lista
de CVars — é entrada obsoleta de uma versão anterior. O CVar real é
`gl_bloom_amount` (float, default `1.4`). O `gl_bloom` do mod simplesmente não
faz nada no build atual.

### Descobrindo valores em tempo de execução

O GZDoom 4.11 deste mod **remove** a maioria dos comandos de console — o
ZScript apaga `help`, `benchmark`, `version`, `demo`, `netdemo`… Restam alguns,
e a forma de descobrir o que existe é perguntar e ler a resposta:

```bash
fnaf-doom --log +cvarlist +ccmdlist +stat +version +quit +benchmark
```

```bash
grep -oE 'Unknown command "[a-z_0-9]+"' /tmp/fnaf-doom.log | sort -u
```

```
Unknown command "ccmdlist"
Unknown command "demo"
Unknown command "benchmark"
Unknown command "version"
```

O que **não** aparece na lista de erro existe. `cvarlist` imprime todos os CVars
com o valor atual e um marcador de seção — `A` indica os que o GZDoom persiste
no `settings.ini`, ou seja, os que realmente valem no próximo boot:

```
A     gl_multisample = 2
A     gl_ssao = 1
A     gl_shadowmap_quality = 1024
A     gl_texture_filter_anisotropic = 8
A     vid_scalemode = 0
```

Isso também revelou que o mod sobrescreve `vid_scale_customwidth` para `320` e
`vid_scale_customheight` para `200` no ZScript, anulando o `-1` do
`settings.ini` — ou seja, mexer só no `.ini` não bastava.

---

## 5. O enum `vid_scalemode`

Os valores não são documentados e a ordem é contraintuitiva
(`vid_scalemode=3` **não** é "custom"). Medi-se empiricamente, uma execução por
valor, lendo a linha `Resolution:` do log:

```bash
for N in 0 1 2 3 4 5; do
  fnaf-doom --log "+vid_scalemode $N" &
  until grep -qE '^Resolution:' /tmp/fnaf-doom.log 2>/dev/null; do sleep 1; done
  echo "$N -> $(grep -m1 '^Resolution:' /tmp/fnaf-doom.log)"
  pkill -f gzdoom.exe
done
```

| valor | resolução | leitura |
|---:|---|---|
| 0 | 1920x1080 | normal (nativa) |
| 1 | 711x400 | High DPI |
| 2 | 640x400 | off |
| 3 | 960x600 | — |
| 4 | 1280x800 | — |
| **5** | **1600x900** | **custom** (era 1600x900 no teste) |

O `5` usa `vid_scale_customwidth/height` — e devolveu exatamente 1600x900, o
valor que estava no `.ini` no momento. Método que funciona em qualquer build:
coloque um valor absurdo, veja o que sai.

---

## 6. Resumo do que foi consertado

| # | Problema | Correção |
|---|---|---|
| 1 | `[IWADSearch.Directories]` vazia → `Cannot find a game IWAD` | `Path=$PROGDIR` |
| 2 | `FDLauncher.exe` é Windows | script de shell que monta o mesmo comando |
| 3 | Preset do mod pesado demais para iGPU (22 FPS) | perfil medido, ~50 FPS |
| 4 | `vid_preferbackend` ambíguo | fixado em `1` (Vulkan) |
| 5 | `vid_scalemode` sem documentação | medido: `5` = custom |
| 6 | `gl_bloom` obsoleto | `gl_bloom_amount` é o CVar real |
| 7 | `cl_capfps` / vsync degradando o pacing | ambos desligados |

Próximo: [02-performance.md](02-performance.md).
