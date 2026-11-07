#!/usr/bin/env python3
"""Reference values for tests/test_tcas.f95 (ThermalCascade, module
thermalcascade).

Independent of the Fortran: everything here is built from the model's
definition in doc/design/burn_models.md ("ThermalCascade", as repaired), at
50 digits (mpmath), not from module thermalcascade's forms (its series for
1 - exp(-x), its test at T = TC):

- The rate:  r = HT (1 - lam) max(T - TC, 0)^GT (1 + P_s/PR)^NS, per unit
  (1 - lam), so r = HT max(T - TC, 0)^GT (1 + P_s/PR)^NS; 0 at or below TC
  for every GT (0^0 taken as 0 there, the repair's meaning).
- The exact step at a fixed rate: 1 - lam2 = (1 - lam1) exp(-r dt), and
  1 - exp(-x) by mpmath's own exp (expm1), for x from 1e-16 to 50.
- The cascade at constant volume: at fixed rho and e the closure's T is
  linear in lam, T = Ta + b lam (b = (e_c + Q)/C_V: each lam adds the cold
  energy and the heat of reaction to vartheta), so the time to reach lam*
  from 0 is the integral of dlam/(HT (1 - lam) (Ta + b lam - TC)^GT S),
  S = (1 + P_s/PR)^NS, by mpmath's quadrature. Two cases: GT = 1 (closed
  form too, checked here against the quadrature) and GT = 1.5.

Needs Python 3 and mpmath (pip install mpmath).

    python3 tests/tcas_reference.py > rows.txt

prints the Fortran rows to paste into test_tcas.f95.
D. E. Kittell (with Claude), 11/07/26.
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

def rate(T, Ps, HT, TC, GT, NS, PR):
    T, Ps, HT, TC, GT, NS, PR = [mp.mpf(v) for v in (T, Ps, HT, TC, GT, NS, PR)]
    if not T > TC:
        return mp.mpf(0)
    return HT*(T - TC)**GT*(1 + max(Ps, 0)/PR)**NS

#*** 1. The rate: (T, P_s, HT, TC, GT, NS, PR), its value.
rates = [
    ('740', '11', '1e-4', '600', '1.5', '2', '7'),      # the example's scale
    ('740', '11', '1e-4', '600', '1', '2', '7'),
    ('740', '0', '1e-4', '600', '1.5', '2', '7'),       # P_s = 0
    ('740', '-3', '1e-4', '600', '1.5', '2', '7'),      # P_s < 0: as 0
    ('3500', '25', '2e-6', '600', '2.25', '0.5', '7'),  # hot, GT non-integer
    ('601', '11', '1e-4', '600', '1.5', '2', '7'),      # just above TC
    ('600', '11', '1e-4', '600', '1.5', '2', '7'),      # at TC: 0
    ('599', '11', '1e-4', '600', '0', '2', '7'),        # below TC, GT = 0: 0
    ('601', '11', '0.25', '600', '0', '2', '7'),        # GT = 0 above TC
    ('900', '11', '1e-4', '0', '1', '0', '7'),          # TC = 0, NS = 0
    ('900', '11', '0', '600', '1', '2', '7'),           # HT = 0
]
print(f'! {len(rates)} rate rows: T, P_s, HT, TC, GT, NS, PR, r')
for i, r in enumerate(rates):
    print(row('rate_t', [f(x) for x in r] + [f(rate(*r))], i == len(rates) - 1))

#*** 2. 1 - exp(-x).
xs = ['1e-16', '1e-12', '1e-8', '1e-4', '0.01', '0.05', '0.4999', '0.5',
      '1', '10', '50']
print(f'! {len(xs)} rows: x, 1 - exp(-x)')
for i, x in enumerate(xs):
    print(row('om_t', [f(x), f(-mp.expm1(-mp.mpf(x)))], i == len(xs) - 1))

#*** 3. The exact step: (lam1, x), lam2 = 1 - (1 - lam1) exp(-x).
steps = [('0', '1e-12'), ('0', '0.03'), ('0', '2'), ('1e-9', '1e-6'),
         ('0.5', '0.7'), ('0.999', '3'), ('0.25', '0')]
print(f'! {len(steps)} step rows: lam1, x = r dt, lam2')
for i, (l, x) in enumerate(steps):
    l2 = mp.mpf(l) + (1 - mp.mpf(l))*(-mp.expm1(-mp.mpf(x)))
    print(row('step_t', [f(l), f(x), f(l2)], i == len(steps) - 1))

#*** 4. The cascade at constant volume: times to lam* = 0.5 and 0.99.
def t_to(lamx, Ta, b, HT, TC, GT, S):
    Ta, b, HT, TC, GT, S = [mp.mpf(v) for v in (Ta, b, HT, TC, GT, S)]
    g = lambda l: 1/(HT*(1 - l)*(Ta + b*l - TC)**GT*S)
    return mp.quad(g, [0, mp.mpf(lamx)/2, lamx])
S = (1 + mp.mpf(11)/7)**2
cases = [('740', '4200', '1e-3', '600', '1'), ('740', '4200', '1e-4', '600', '1.5')]
print('! cascade rows: Ta, b, HT, TC, GT, S = (1 + 11/7)^2, t(0.5), t(0.99)')
for i, (Ta, b, HT, TC, GT) in enumerate(cases):
    t5, t99 = t_to('0.5', Ta, b, HT, TC, GT, S), t_to('0.99', Ta, b, HT, TC, GT, S)
    if GT == '1':      # closed form: partial fractions of 1/((1-l)(A+bl))
        A = mp.mpf(Ta) - mp.mpf(TC); B = mp.mpf(b); k = mp.mpf(HT)*S
        cf = lambda l: (mp.log((A + B*l)/A) - mp.log(1 - l))/(k*(A + B))
        assert abs(cf(mp.mpf('0.5')) - t5) < mp.mpf('1e-40')
        assert abs(cf(mp.mpf('0.99')) - t99) < mp.mpf('1e-40')
    print(row('casc_t', [f(Ta), f(b), f(HT), f(TC), f(GT), f(S), f(t5),
                         f(t99)], i == len(cases) - 1))
