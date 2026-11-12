#!/usr/bin/env python3
"""Reference values for tests/test_ffire.f95 (FlashFire, module flashfire).

Independent of the Fortran: everything here is built from the model's
definition in doc/design/burn_models.md ("FlashFire", and "Step 6,
FlashFire: the plan"), at 50 digits (mpmath), not from module flashfire's
forms (its RK4 sub-steps, its tests):

- The rate:  r = KFF (1 - lam)^AFF lam^BFF exp(-TA/T) (1 + max(P_s, 0)/PR)^NS
  for 0 < lam < 1 and T > 0; 0 otherwise.
- At a fixed T with BFF = 0 the rate is c (1 - lam)^AFF, c = KFF
  exp(-TA/T) S, and from lam0 at t = 0, exactly,
      (1 - lam)^(1 - AFF) = (1 - lam0)^(1 - AFF) - (1 - AFF) c t   (AFF /= 1)
      1 - lam = (1 - lam0) exp(-c t)                              (AFF = 1)
  (for AFF < 1, lam = 1 from the finite time the first reaches 0).
- The cascade at constant volume: at fixed rho and e the closure's T is
  linear in lam, T = Ta + b lam (b = (e_c + Q)/C_V), so the time to reach
  lam* from the seed lam0 is the integral of dlam/r(lam, Ta + b lam), by
  mpmath's quadrature. FlashFire's T follows lam within the step (DK,
  11/12/26), so at constant volume its step should match this to its
  integration error alone, whatever dt.

Needs Python 3 and mpmath (pip install mpmath).

    python3 tests/ffire_reference.py > rows.txt

prints the Fortran rows to paste into test_ffire.f95.
D. E. Kittell (with Claude), 11/12/26.
"""
import mpmath as mp
mp.mp.dps = 50

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
    """A type constructor, wrapped to Fortran lines of 72 characters."""
    lines, cur = [], f'   {name}( '
    for i, v in enumerate(vals):
        piece = v + (', ' if i < len(vals) - 1 else ' )')
        if len(cur) + len(piece) > 72:
            lines.append(cur.rstrip() + ' &')
            cur = '      '
        cur += piece
    lines.append(cur + (' /)' if last else ', &'))
    return '\n'.join(lines)

def rate(lam, T, Ps, K, A, B, TA, NS, PR):
    lam, T, Ps, K, A, B, TA, NS, PR = [mp.mpf(v) for v in
                                       (lam, T, Ps, K, A, B, TA, NS, PR)]
    if not (0 < lam < 1 and T > 0):
        return mp.mpf(0)
    return K*(1 - lam)**A*lam**B*mp.exp(-TA/T)*(1 + max(Ps, 0)/PR)**NS

#*** 1. The rate: (lam, T, P_s, KFF, AFF, BFF, TA, NS, PR), its value.
rates = [
    ('0.3', '900', '11', '400', '1', '0.5', '6000', '2', '7'),   # the example's
    ('1e-4', '740', '11', '400', '1', '0.5', '6000', '2', '7'),  # at the seed
    ('0.3', '900', '0', '400', '1', '0.5', '6000', '2', '7'),    # P_s = 0
    ('0.3', '900', '-3', '400', '1', '0.5', '6000', '2', '7'),   # P_s < 0: as 0
    ('0.999', '3500', '25', '2e5', '2', '0', '12000', '0.5', '7'),  # BFF = 0
    ('0.5', '900', '11', '3', '0', '2.5', '0', '1', '1'),        # AFF = 0, TA = 0
    ('1', '900', '11', '400', '0', '0.5', '6000', '2', '7'),     # lam = 1: 0
    ('0', '900', '11', '400', '1', '0', '6000', '2', '7'),       # lam = 0: 0
    ('0.3', '0', '11', '400', '1', '0.5', '6000', '2', '7'),     # T = 0: 0
    ('0.3', '-5', '11', '400', '1', '0.5', '6000', '2', '7'),    # T < 0: 0
    ('0.3', '900', '11', '0', '1', '0.5', '6000', '2', '7'),     # KFF = 0: 0
]
print(f'! {len(rates)} rate rows: lam, T, P_s, KFF, AFF, BFF, TA, NS, PR, r')
for i, r in enumerate(rates):
    print(row('rate_t', [f(x) for x in r] + [f(rate(*r))], i == len(rates) - 1))

#*** 2. Fixed T, BFF = 0: lam(t) from lam0, closed form. (lam0, c, AFF, t)
def lam_fixed(l0, c, A, t):
    l0, c, A, t = [mp.mpf(v) for v in (l0, c, A, t)]
    if A == 1:
        return 1 - (1 - l0)*mp.exp(-c*t)
    y = (1 - l0)**(1 - A) - (1 - A)*c*t
    if y <= 0:
        return mp.mpf(1)
    return 1 - y**(1/(1 - A))
fixed = [('1e-4', '2', '1', '0.5'), ('1e-4', '2', '0.5', '0.3'),
         ('1e-4', '2', '2', '1.5'), ('0.2', '5', '1.5', '0.1'),
         ('1e-4', '2', '0.5', '2')]                              # burnt out
print(f'! {len(fixed)} fixed-T rows (BFF = 0): lam0, c, AFF, t, lam(t)')
for i, (l0, c, A, t) in enumerate(fixed):
    print(row('fix_t', [f(l0), f(c), f(A), f(t), f(lam_fixed(l0, c, A, t))],
              i == len(fixed) - 1))

#*** 3. The cascade at constant volume: (Ta, b, Ps, KFF, AFF, BFF, TA, NS,
#***    PR, lam0) and the times from the seed to lam = 0.5 and 0.99.
def t_to(lx, Ta, b, Ps, K, A, B, TA, NS, PR, l0):
    Ta, b, l0, lx = [mp.mpf(v) for v in (Ta, b, l0, lx)]
    g = lambda l: 1/rate(l, Ta + b*l, Ps, K, A, B, TA, NS, PR)
    pts = [l0] + [x for x in (mp.mpf('1e-3'), mp.mpf('1e-2'), mp.mpf('0.1'),
                              mp.mpf('0.3'), mp.mpf('0.5'), mp.mpf('0.9'))
                  if l0 < x < lx] + [lx]
    return mp.quad(g, pts)
cascs = [('740', '4200', '11', '400', '1', '0.5', '6000', '2', '7', '1e-4'),
         ('740', '4200', '11', '2e5', '2', '0', '12000', '2', '7', '1e-4'),
         ('800', '4000', '5', '50', '0.5', '1', '3000', '1', '7', '1e-3')]
print('! cascade rows: Ta, b, P_s, KFF, AFF, BFF, TA, NS, PR, LAM0, t(0.5), t(0.99)')
for i, c in enumerate(cascs):
    print(row('casc_t', [f(x) for x in c] + [f(t_to('0.5', *c)),
                                             f(t_to('0.99', *c))],
              i == len(cascs) - 1))
