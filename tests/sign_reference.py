#!/usr/bin/env python3
"""Reference values for tests/test_sign.f95 (StochasticIgnite, module
stochignite).

Independent of the Fortran:
- AS241's normal deviates against the exact inverse of the normal
  distribution at 50 digits (mpmath: sqrt(2) erfinv(2u - 1)), over the
  central and both tail ranges, u from 2^-54 to 1 - 2^-53. Each u is
  the double nearest the decimal, taken exactly: near u = 1/2 and 1 the
  deviate is sensitive to the last bit of u, not to AS241.
- The generator's bits from Python's own (unbounded) integers: SplitMix64,
  m(x) = mix(x + 0x9E3779B97F4A7C15 mod 2^64), chained as
  m(m(m(m(SEED) xor j) xor n) xor s), u = ((x >> 12) + 1/2) 2^-52, for
  bins j of either sign (j taken as its 64-bit two's complement), so the
  Fortran's 16-bit pieces can be checked bit for bit.
- Bin j's starting Z: table entry modulo(SEED + 7919 j, 20000) + 1 of
  module random (read from src/modules/rand_mod.f95), through the exact
  inverse normal at 50 digits.
- The floored mean rate, E[max(mu + sigma Z, 0)] = mu Phi(mu/sigma) +
  sigma phi(mu/sigma), Z ~ N(0, 1), at 50 digits.

Needs Python 3 and mpmath.

    python3 tests/sign_reference.py > rows.txt

prints the Fortran rows to paste into test_sign.f95.
D. E. Kittell (with Claude), 11/12/26.
"""
import os, re
import mpmath as mp
mp.mp.dps = 50
M64 = (1 << 64) - 1

def f(x):
    """A Fortran real(dp) literal, 20 significant digits."""
    x = mp.mpf(x)
    if x == 0:
        return '0.0_dp'
    s = mp.nstr(x, 20, min_fixed=1, max_fixed=0, strip_zeros=False)
    if 'e' not in s:
        return (s if '.' in s else s + '.0') + '_dp'
    m, e = s.split('e')
    return f'{m}e{int(e)}_dp'

def row(name, vals, last):
    lines, cur = [], f'   {name}( '
    for i, v in enumerate(vals):
        piece = v + (', ' if i < len(vals) - 1 else ' )')
        if len(cur) + len(piece) > 72:
            lines.append(cur.rstrip() + ' &')
            cur = '      '
        cur += piece
    lines.append(cur + (' /)' if last else ', &'))
    return '\n'.join(lines)

def splitmix(x):
    x = (x + 0x9E3779B97F4A7C15) & M64
    z = ((x ^ (x >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    return z ^ (z >> 31)

def uniform(seed, j, n, s):
    x = splitmix(seed & M64)
    x = splitmix(x ^ (j & M64))
    x = splitmix(x ^ (n & M64))
    x = splitmix(x ^ (s & M64))
    return (mp.mpf(x >> 12) + mp.mpf('0.5'))*mp.mpf(2)**-52   # exact

def ndev(u):
    return mp.sqrt(2)*mp.erfinv(2*mp.mpf(u) - 1)

#*** 1. AS241: u and the exact deviate.
us = ['2^-54', '1e-20', '1e-10', '1e-5', '0.001', '0.02425', '0.0749',
      '0.075', '0.2', '0.4999', '0.5', '0.5001', '0.8', '0.925', '0.9251',
      '0.99', '0.99999', '1 - 2^-53']
vals = []
for u in us:
    if u == '2^-54':
        x = mp.mpf(2)**-54
    elif u == '1 - 2^-53':
        x = 1 - mp.mpf(2)**-53
    else:
        x = mp.mpf(float(u))    # the double the Fortran reads, exactly
    vals.append((x, ndev(x)))
print(f'! {len(vals)} AS241 rows: u, the deviate')
for i, (u, z) in enumerate(vals):
    print(row('dev_t', [f(u), f(z)], i == len(vals) - 1))

#*** 2. The generator: (seed, j, n, s) and u, exactly (53 bits).
cases = [(0, 0, 0, 0), (12345, 0, 1, 1), (12345, 7, 1, 1), (12345, -7, 1, 1),
         (19999, -123456789, 987654, 3), (1, 2**40 + 5, 10**9, 999),
         (777, 3, 2, 1), (777, 3, 2, 2)]
print(f'! {len(cases)} generator rows: seed, j, n, s (integers), u')
for i, (sd, j, n, s) in enumerate(cases):
    u = uniform(sd, j, n, s)
    print(row('gen_t', [f'{sd}_int64', f'{j}_int64', f'{n}_int64',
                        f'{s}_int64', f(u)], i == len(cases) - 1))

#*** 3. Bin j's starting Z from the table.
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                        'src', 'modules', 'rand_mod.f95')).read()
table = [mp.mpf(v) for v in re.findall(r'(-?[0-9]*\.[0-9]+)_z', src)]
assert len(table) == 20000
zcases = [(0, 0), (12345, 3), (12345, -3), (19999, 250000), (42, -1),
          (19999, 2**62 - 1), (5, -2**62)]                  # no overflow
print(f'! {len(zcases)} starting-Z rows: seed, j (integers), Z')
for i, (sd, j) in enumerate(zcases):
    z = ndev(table[(sd + 7919*j) % 20000])
    print(row('z0_t', [f'{sd}_int64', f'{j}_int64', f(z)],
              i == len(zcases) - 1))

#*** 4. The floored mean rate.
rcases = [('2', '1'), ('2', '2'), ('2', '6'), ('1', '0.5')]
print(f'! {len(rcases)} floored-rate rows: mu, sigma, E[max(mu + sigma Z, 0)]')
for i, (m, sg) in enumerate(rcases):
    m, sg = mp.mpf(m), mp.mpf(sg)
    x = m/sg
    r = m*mp.ncdf(x) + sg*mp.npdf(x)
    print(row('flr_t', [f(m), f(sg), f(r)], i == len(rcases) - 1))
