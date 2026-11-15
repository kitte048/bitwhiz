#!/usr/bin/env python3
"""Reference values for tests/test_claude.f95 (CLAUDE, module claude).

Independent of the Fortran: built at 50 digits (mpmath) from the model's
definition in doc/design/burn_models.md ("CLAUDE", and "Step 9, CLAUDE:
the plan"), not from module claude's forms (its moments, its J_k):

- Avrami's extended volume, directly: for centers lit at a rate ndot(t)
  and growing at G(t) (both constant over each step of a history), each
  quenched at the rate q = 1/TQ, the expected extended volume at time T is
      V(T) = int_0^T ndot(t0) [ e^(-q(T-t0)) (4pi/3) R(t0,T)^3
             + int_t0^T q e^(-q(tau-t0)) (4pi/3) R(t0,tau)^3 dtau ] dt0,
  R(t0,t) = int_t0^t G; lam = 1 - exp(-V). By nested quadrature, step by
  step; with q = 0 (TQ = 1e30) too.
- Every center lit at once, G constant: lam = 1 - exp(-(pi/6) that^3),
  that = t/t_c, t_c = 1/(2 G N^(1/3)) (Hill and Zimmermann).
- The entropy above the reference isentrope at a state (eta, e) with e_c
  given: s = int from e_c to e of de'/T(e') at fixed v (heating at fixed
  volume from the isentrope), T(e') = T0 e^(G0 eta) + (e' - e_c)/C_V, by
  quadrature, not the closed form.
- n(w2) - n(w1), n(w) = NMAX (1 - exp(-(w/W0)^KW)); J_k by quadrature.

Needs Python 3 and mpmath.

    python3 tests/claude_reference.py > rows.txt

prints the Fortran rows to paste into test_claude.f95.
D. E. Kittell (with Claude), 11/14/26.
"""
import mpmath as mp
mp.mp.dps = 50
M = mp.mpf

def f(x):
    """A Fortran real(dp) literal, 20 significant digits."""
    x = M(x)
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

#*** 1. A history: 8 steps of dt = 0.05 us, centers lit dn_k in step k
#***    (evenly through it), growth G_k (mm/us). lam at the end, by the
#***    extended volume, for q = 0 and q = 4/us (TQ = 0.25).
DT = M('0.05')
DN = [M(x) for x in ('20', '0', '50', '10', '0', '0', '30', '5')]      # 1/mm^3
GS = [M(x) for x in ('0.1', '0.3', '0.2', '0', '0.5', '0.4', '0.4', '1')]
def R(t0, t):
    # int_t0^t G, G piecewise constant on the steps
    if t <= t0:
        return M(0)
    s = M(0)
    for k, g in enumerate(GS):
        a, b = k*DT, (k + 1)*DT
        lo, hi = max(a, t0), min(b, t)
        if hi > lo:
            s += g*(hi - lo)
    return s
def V(q, T):
    tot = M(0)
    for k, dn in enumerate(DN):
        a, b = k*DT, min((k + 1)*DT, T)
        if dn == 0 or b <= a:
            continue
        rate = dn/DT
        def inner(t0):
            v = mp.exp(-q*(T - t0))*R(t0, T)**3
            if q > 0:
                pts = [t0] + [j*DT for j in range(len(GS) + 1) if t0 < j*DT < T] + [T]
                v += mp.quad(lambda tau: q*mp.exp(-q*(tau - t0))*R(t0, tau)**3, pts)
            return rate*v
        tot += mp.quad(inner, [a, b])
    return 4*mp.pi/3*tot
T = len(DN)*DT
print('! 2 history rows: q (1/us), lam at the end')
for i, q in enumerate([M(0), M(4)]):
    print(row('his_t', [f(q), f(1 - mp.exp(-V(q, T)))], i == 1))

#*** 2. All lit at once: (N, G, t), lam = 1 - exp(-(pi/6) that^3).
alls = [('1000', '0.3', '0.04'), ('125', '0.5', '0.3'), ('8', '1', '1')]
print(f'! {len(alls)} all-at-once rows: N, G, t, lam')
for i, (n, g, t) in enumerate(alls):
    tc = 1/(2*M(g)*M(n)**(M(1)/3))
    lam = 1 - mp.exp(-mp.pi/6*(M(t)/tc)**3)
    print(row('all_t', [f(n), f(g), f(t), f(lam)], i == len(alls) - 1))

#*** 3. The entropy: (e, e_c, eta, C_V, T0, G0), s in J/(g K), by
#***    quadrature of de/T at fixed volume.
ents = [('0.97', '0.33', '0.2593', '1.1633418e-3', '298', '1.2'),
        ('0.25', '0.05', '0.1', '1.1633418e-3', '298', '1.2'),
        ('0.05', '0.0', '0.0', '0.9e-3', '300', '2.0'),
        ('1.5', '0.8', '0.32', '1.1633418e-3', '298', '1.2')]
print(f'! {len(ents)} entropy rows: e, e_c, eta, C_V, T0, G0, s')
for i, (e, ec, eta, cv, t0, g0) in enumerate(ents):
    ts = M(t0)*mp.exp(M(g0)*M(eta))
    s = mp.quad(lambda x: 1/(ts + (x - M(ec))/M(cv)), [M(ec), M(e)])
    print(row('ent_t', [f(e), f(ec), f(eta), f(cv), f(t0), f(g0), f(1000*s)],
              i == len(ents) - 1))

#*** 4. Centers lit: (w1, w2, NMAX, W0, KW), n(w2) - n(w1).
dns = [('0', '0.66', '1000', '0.6', '4'), ('0.3', '0.31', '1000', '0.6', '4'),
       ('0.6', '0.6000001', '1000', '0.6', '4'), ('0.1', '2', '50', '0.5', '1'),
       ('1e-16', '0.66', '1000', '0.66', '30'),      # a one-step shock, KW
       ('2e-16', '0.66', '1000', '0.66', '4')]       # large: no overflow
print(f'! {len(dns)} lighting rows: w1, w2, NMAX, W0, KW, dn')
D = lambda x: M(float(x))       # the double the Fortran reads, exactly: a
                                # rise of 1e-7 depends on w's last bits
for i, (w1, w2, nm, w0, kw) in enumerate(dns):
    n = lambda w: D(nm)*(1 - mp.exp(-(D(w)/D(w0))**D(kw)))
    print(row('dn_t', [f(w1), f(w2), f(nm), f(w0), f(kw), f(n(w2) - n(w1))],
              i == len(dns) - 1))

#*** 5. J_k = int_0^dt u^k e^(-q u) du: (dt, q), J_0 to J_4.
jks = [('0.05', '4'), ('0.05', '1e-6'), ('0.3', '40'), ('2', '0.6'),
       ('1', '1.0'), ('1', '1.999'), ('1', '2.001'), ('0.5', '6')]  # the switch
print(f'! {len(jks)} J rows: dt, q, J_0 .. J_4')
for i, (dt, q) in enumerate(jks):
    js = [mp.quad(lambda u: u**k*mp.exp(-M(q)*u), [0, M(dt)]) for k in range(5)]
    print(row('jk_t', [f(dt), f(q)] + [f(x) for x in js], i == len(jks) - 1))
