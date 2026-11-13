#!/usr/bin/env python3
"""Reference values for tests/test_halo.f95 (HALO, module halo).

Independent of the Fortran: built at 50 digits (mpmath) from the model's
definition in doc/design/burn_models.md ("HALO", and "Step 8, HALO: the
plan"), not from module halo's forms:

- The activation measure along a Rayleigh line, P rising linearly in v
  from P_a at v_a to P_b at v_b: the converged integral of sqrt(P) |dv|,
      (2/3) |v_b - v_a| (P_b^(3/2) - P_a^(3/2))/(P_b - P_a),
  and the scheme's sum over N equal steps in v, each sqrt(De |Dv|) with De
  the work over that step (exact: the mean of P times |Dv|). N = 1 from
  rest is 3/(2 sqrt 2) of the integral.
- The activated fraction Erf((E_D/ED0)^BETAH).
- Dissipation alone at a fixed lam: eta0 exp(-(1 - lam)^DELTA t/TAUD).
- The burn at fixed eta and P: lam(t) = 1 - exp(-(K t)^d), K = KB
  eta^(1/d) (max(P, 0)/PR)^NH (KJMA), and one step's lam from s1.

Needs Python 3 and mpmath.

    python3 tests/halo_reference.py > rows.txt

prints the Fortran rows to paste into test_halo.f95.
D. E. Kittell (with Claude), 11/13/26.
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
    lines, cur = [], f'   {name}( '
    for i, v in enumerate(vals):
        piece = v + (', ' if i < len(vals) - 1 else ' )')
        if len(cur) + len(piece) > 72:
            lines.append(cur.rstrip() + ' &')
            cur = '      '
        cur += piece
    lines.append(cur + (' /)' if last else ', &'))
    return '\n'.join(lines)

def M(x):
    return mp.mpf(x)

#*** 1. The measure: (v_a, P_a, v_b, P_b, N), the scheme's sum, the integral.
def rayleigh(va, Pa, vb, Pb, N):
    va, Pa, vb, Pb = M(va), M(Pa), M(vb), M(Pb)
    P = lambda v: Pa + (Pb - Pa)*(va - v)/(va - vb)
    tot = mp.mpf(0)
    for k in range(N):
        v1 = va + (vb - va)*k/M(N)
        v2 = va + (vb - va)*(k + 1)/M(N)
        de = (P(v1) + P(v2))/2*(v1 - v2)          # the work, exact (P linear)
        tot += mp.sqrt(de*(v1 - v2))
    I = M(2)/3*(va - vb)*(Pb**M(1.5) - Pa**M(1.5))/(Pb - Pa)
    return tot, I
paths = [('0.625', '0', '0.4636', '11', 1), ('0.625', '0', '0.4636', '11', 10),
         ('0.625', '0', '0.4636', '11', 1000), ('0.55', '4', '0.47', '11', 1),
         ('0.55', '4', '0.47', '11', 50)]
print(f'! {len(paths)} measure rows: v_a, P_a, v_b, P_b, N, the sum, the integral')
for i, (va, Pa, vb, Pb, N) in enumerate(paths):
    t, I = rayleigh(va, Pa, vb, Pb, N)
    print(row('ed_t', [f(va), f(Pa), f(vb), f(Pb), str(N), f(t), f(I)],
              i == len(paths) - 1))

#*** 2. Activation: (E_D, ED0, BETAH), Erf((E_D/ED0)^BETAH).
acts = [('0.39', '0.4', '4'), ('0.33', '0.4', '4'), ('0.1', '0.4', '4'),
        ('0.8', '0.4', '4'), ('0.25', '0.3', '1'), ('0.25', '0.3', '2.5')]
print(f'! {len(acts)} activation rows: E_D, ED0, BETAH, Erf((E_D/ED0)^BETAH)')
for i, (e, e0, b) in enumerate(acts):
    print(row('act_t', [f(e), f(e0), f(b), f(mp.erf((M(e)/M(e0))**M(b)))],
              i == len(acts) - 1))

#*** 3. Dissipation alone: (eta0, lam, DELTA, TAUD, t), eta(t).
diss = [('0.8', '0', '2', '0.25', '1'), ('0.8', '0.3', '2', '0.25', '1'),
        ('0.5', '0.6', '0', '0.1', '0.3'), ('1', '0.9', '0.5', '2', '3')]
print(f'! {len(diss)} dissipation rows: eta0, lam, DELTA, TAUD, t, eta(t)')
for i, (e0, l, d, tau, t) in enumerate(diss):
    k = (1 - M(l))**M(d)/M(tau) if M(d) > 0 else 1/M(tau)
    print(row('dis_t', [f(e0), f(l), f(d), f(tau), f(t),
                        f(M(e0)*mp.exp(-k*M(t)))], i == len(diss) - 1))

#*** 4. The burn at fixed eta and P: (eta, P, KB, DFRAC, NH, PR, t), lam(t).
burns = [('0.84', '11', '0.5', '3', '2', '7', '0.4'),
         ('0.84', '11', '0.5', '2.3', '2', '7', '0.4'),
         ('0.3', '11', '2', '2', '1', '7', '0.25'),
         ('1', '-2', '1', '2', '0', '7', '0.5'),      # NH = 0: P does not matter
         ('0.5', '5', '1', '3', '2', '7', '0.05')]    # small lam
print(f'! {len(burns)} burn rows: eta, P, KB, DFRAC, NH, PR, t, lam(t)')
for i, (e, P, kb, d, nh, pr, t) in enumerate(burns):
    fp = (max(M(P), 0)/M(pr))**M(nh) if M(nh) > 0 else M(1)
    K = M(kb)*M(e)**(1/M(d))*fp
    lam = 1 - mp.exp(-(K*M(t))**M(d))
    print(row('brn_t', [f(e), f(P), f(kb), f(d), f(nh), f(pr), f(t), f(lam)],
              i == len(burns) - 1))
