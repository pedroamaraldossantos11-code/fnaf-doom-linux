#!/usr/bin/env python3
"""Gera o icone do FNAF Doom a partir do logo que vem dentro do proprio jogo.

O logo esta em FNAFDoom.ipk3 -> graphics/title/M_DOOM.png (123x60, RGBA).
Fazemos um quadrado 256x256 com fundo escuro e vinheta, no tom do jogo.

    python3 make-icon.py --jogo ~/Downloads/game --saida fnaf-doom.png

Requer Pillow.
"""
import argparse
import pathlib
import subprocess
import sys
import zipfile

LUMP = "graphics/title/M_DOOM.png"


def extrair(gamedir: pathlib.Path, destino: pathlib.Path) -> pathlib.Path:
    ipk3 = gamedir / "FNAFDoom.ipk3"
    if not ipk3.is_file():
        sys.exit(f"ERRO: {ipk3} nao encontrado. Baixe o jogo antes.")
    destino.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ipk3) as z:
        try:
            z.extract(LUMP, destino)
        except KeyError:
            sys.exit(f"ERRO: {LUMP} nao existe dentro de {ipk3.name}")
    return destino / LUMP


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jogo", default="~/Downloads/game", help="pasta do jogo")
    ap.add_argument("--saida", default="fnaf-doom.png", help="PNG de saida")
    ap.add_argument("--tamanho", type=int, default=256)
    args = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "--user", "pillow"], check=False)
        from PIL import Image

    gamedir = pathlib.Path(args.jogo).expanduser()
    logo_path = extrair(gamedir, pathlib.Path("/tmp/fnaf-doom-icon"))

    logo = Image.open(logo_path).convert("RGBA")
    S = args.tamanho

    # fundo escuro com leve vinheta radial
    img = Image.new("RGBA", (S, S))
    px = img.load()
    raio = S * 0.71
    for y in range(S):
        for x in range(S):
            d = (((x - S / 2) ** 2 + (y - S / 2) ** 2) ** 0.5) / raio
            v = int(26 * (1 - min(1.0, d))) + 11
            px[x, y] = (v, v, min(255, v + 4), 255)

    largura = int(S * 0.78)
    logo = logo.resize((largura, max(1, int(largura * logo.height / logo.width))), Image.LANCZOS)
    img.alpha_composite(logo, ((S - logo.width) // 2, (S - logo.height) // 2))

    out = pathlib.Path(args.saida)
    img.convert("RGB").save(out)
    print(f"icone gerado: {out} ({S}x{S})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
