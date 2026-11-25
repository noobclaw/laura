# Mochi's friends: the same head recoloured. Writes two board tokens (normal, joy) for each coat.
import os, re
from shiba import head, bandana, svg
OUT = os.path.join(os.path.dirname(__file__), '..', 'out')
COATS = {
 'K': {  # Kuro, black and tan, pink bandana
  'FFC888': '6E6676', 'F7A050': '4C4553', 'E27A30': '342E3A', 'C9621F': '221D27', 'FDB468': '564E5C', 'CC6322': '2A2430', 'F09040': '3A3340',
  'FFD9A8': '8A8292', 'FFC587': '6E6676', 'E88A43': '2A2430', 'B4561C': '000000', 'FFF6EA': 'F2B26E', 'FFE6C2': '9A92A6', 'FFE9CC': '8A8296',
  'C9F4E4': 'FFD9E4', '5FCBA8': 'F0709A', '0B6B55': '8A2348'},
 'S': {  # Shiro, cream white, sky bandana
  'FFC888': 'FFFFFF', 'F7A050': 'FFF5E6', 'E27A30': 'F4E0C6', 'C9621F': 'E0C4A0', 'FDB468': 'FFF1DE', 'CC6322': 'E2C6A2', 'F09040': 'F6E6CF',
  'FFD9A8': 'FFFFFF', 'FFC587': 'FBEFE0', 'E88A43': 'E6CFAE', 'B4561C': 'B08A5A', 'FFE6C2': 'FFFFFF', 'FFE9CC': 'FFFFFF',
  'C9F4E4': 'D6ECFF', '5FCBA8': '5AA8F0', '0B6B55': '1E4F8A'},
 'G': {  # Goma, sesame brown, yellow bandana
  'FFC888': 'DDBB9E', 'F7A050': 'BC8F6C', 'E27A30': '966B4B', 'C9621F': '744F37', 'FDB468': 'C49C7A', 'CC6322': '7A5238', 'F09040': 'A87A58',
  'FFD9A8': 'E6CDB6', 'FFC587': 'CFA88A', 'E88A43': '7A5238', 'B4561C': '5A3A22', 'FFE6C2': 'F0DAC6', 'FFE9CC': 'EAD2BC',
  'C9F4E4': 'FFF3C4', '5FCBA8': 'F2B632', '0B6B55': '8A6208'}}
def recolour(text, m):
    return re.sub('#(' + '|'.join(m) + ')', lambda x: '#' + m[x.group(1)], text)
shadow = '<ellipse cx="256" cy="478" rx="150" ry="18" fill="#3A2A20" opacity=".16" filter="url(#blur6)"/>'
for c, m in COATS.items():
    for i, (e, mo) in enumerate((('open', 'smile'), ('joy', 'open')), 1):
        open(os.path.join(OUT, f'{c}{i}_token.svg'), 'w').write(recolour(svg(512, 512, shadow + bandana() + head(e, mo), px=1024), m))
