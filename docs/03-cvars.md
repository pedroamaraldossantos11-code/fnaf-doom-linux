# 03 — CVars

Referência rápida dos CVars usados no preset final, e o método para
descobrir outros — útil porque o FNAF Doom não tem documentação de settings
e remove quase todos os comandos de console.

---

## Como descobrir os nomes dos CVars

Todo CVar é registrado com o nome como string literal no executável. Então:

```bash
strings -n 4 gzdoom.exe | grep -E '^(r_|gl_|vid_|cl_|v_)[a-z0-9_]+$' | sort -u
```

Sai uma lista de 208 nomes. Para filtrar um efeito específico:

```bash
strings -n 4 gzdoom.exe | grep -E '^(r_|gl_|vid_|cl_)[a-z0-9_]+$' \
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
gl_ssao_bias
gl_ssao_blur
gl_ssao_exponent
gl_ssao_portals
gl_ssao_radius
gl_ssao_strength
gl_texture_filter_anisotropic
r_dynlights
vid_maxfps
vid_scale_customheight
vid_scale_customwidth
vid_scalefactor
vid_scalemode
vid_setscale
vid_vsync
```

### Cuidado com o prefixo

Esperava `r_ssao` e `r_bloom` — o GZDoom 4.10 havia renomeado os CVars de GL
para nomes genéricos. Neste build **4.11.1 não existem**: `grep '^r_'` só
devolve outros nomes, e os efeitos continuam com o prefixo `gl_`. Antes de
assumir a convenção, confira a versão:

```bash
strings gzdoom.exe | grep -m1 -E 'GZDoom version|^g4\.'
```

---

## Como ver os valores atuais

`cvarlist` imprime todos os CVars com o valor atual e um marcador de seção.
O `A` indica os que o GZDoom **persiste** no `settings.ini` — ou seja, os que
realmente valem no próximo boot, em vez de voltarem ao default:

```bash
fnaf-doom --log +cvarlist +quit
grep -E '^A ' /tmp/fnaf-doom.log
```

```
A     gl_multisample = 2
A     gl_ssao = 1
A     gl_shadowmap_quality = 1024
A     gl_texture_filter_anisotropic = 8
A     vid_scalemode = 0
```

Esse comando também revelou que o mod sobrescreve
`vid_scale_customwidth` para `320` e `vid_scale_customheight` para `200` no
ZScript — anulando o `-1` do `settings.ini`. Ou seja, **mexer só no `.ini` não
bastava**; era preciso passar os CVars na linha de comando, que tem prioridade
sobre o ZScript. É o que o launcher faz com `--res`.

---

## Referência dos CVars do preset

### Vídeo

| cvar | valor | efeito |
|---|---:|---|
| `vid_preferbackend` | `1` | 1 = Vulkan, 2 = OpenGL |
| `vid_fullscreen` | `true` | tela cheia |
| `vid_maxfps` | `60` | teto de FPS (o que o driver respeita) |
| `vid_vsync` | `false` | desligado: com <60 FPS gera jitter (47–57) |
| `cl_capfps` | `false` | `true` derruba para ~35 FPS no 4.11 |
| `vid_scalemode` | `5` | 5 = resolução custom (ver tabela abaixo) |
| `vid_scale_customwidth` | `1280` | largura interna |
| `vid_scale_customheight` | `720` | altura interna |

### Efeitos

| cvar | valor | efeito |
|---|---:|---|
| `gl_multisample` | `0` | sem MSAA 2x (custoso em iGPU) |
| `gl_fxaa` | `1` | antisserrilhado barato, substitui o MSAA |
| `gl_ssao` | `0` | o efeito mais caro do preset original |
| `gl_texture_filter_anisotropic` | `4` | 8x custa ~12% dos FPS aqui |
| `gl_plane_reflection` | `false` | um passe de cena extra |
| `gl_light_shadowmap` | `true` | sombras dão profundidade |
| `gl_shadowmap_quality` | `512` | era 1024 no mod; 512 basta a 720p |
| `gl_bloom_amount` | `1.4` | o brilho das lanternas é a atmosfera |
| `r_dynlights` | `true` | a lanterna é dynamic light |

### Idioma

| cvar | valor | efeito |
|---|---:|---|
| `language` | `ptb` | português do Brasil |

> **Atenção ao `gl_bloom`:** o `settings.ini` do mod tem `gl_bloom=true`, mas
> esse nome **não existe** como CVar neste build — é entrada obsoleta de uma
> versão anterior e não faz nada. O CVar real é `gl_bloom_amount`, um float
> (default 1.4). Não confunda os dois.

---

## `vid_scalemode`: medindo o enum

Os valores não são documentados e a ordem é contraintuitiva —
`vid_scalemode=3` **não** é "custom". Mediu-se empiricamente, uma execução por
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

O `5` usa `vid_scale_customwidth/height`, e devolveu exatamente 1600x900 — o
valor que estava no `.ini` no momento. Método que funciona em qualquer build:
coloque um valor absurdo e veja o que sai.

Se a sua build tiver outra enumeração, use `fnaf-doom --res WxH`, que passa os
três CVars pela linha de comando e não depende do `settings.ini`.

---

## Aplicando um CVar sem editar arquivo

A linha de comando tem prioridade sobre o `settings.ini` e sobre o ZScript do
mod — por isso o launcher usa esse mecanismo:

```bash
fnaf-doom --log "+gl_ssao 1" "+gl_texture_filter_anisotropic 8" +quit
grep -E '^A (gl_ssao|gl_texture_filter)' /tmp/fnaf-doom.log
```

Depois de confirmar o valor, coloque no `settings.ini` para ficar permanente.

---

## Descobertas que contrariam a documentação do GZDoom

| expectativa | realidade neste build |
|---|---|
| `r_ssao`, `r_bloom` (nomes do 4.10) | `gl_ssao`, `gl_bloom_amount` |
| `vid_scalemode=3` = custom | `5` = custom |
| `cl_capfps` economiza CPU | derruba 50 → 35 FPS |
| vsync melhora o movimento | com <60 FPS, piora (jitter) |
| `-iwad arq.ipk3` sempre funciona | só se tiver separador de caminho |
| Baixar de 1080p para 720p sempre melhora | Vale; mas de 720p para 648p, não (48 vs ~50) |
| Aqua thumbnail gerado | "Should be 0" no log — o jogo não valida o campo |

Voltar: [README](../README.md) · [01-diagnostico](01-diagnostico.md) ·
[02-performance](02-performance.md)
