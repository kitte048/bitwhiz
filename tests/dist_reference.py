#!/usr/bin/env python3
"""Reference values for tests/test_dist.f95 (the "ref" and "mref" tables).

Independent of the Fortran: every value comes from the textbook definition,
evaluated by mpmath at 50 digits (pip install mpmath):
  beta          F = mpmath.betainc(a, b, 0, x, regularized=True)
  normal        F = mpmath.ncdf
  split normal  F from the normal on each side of the peak
  sinh-arcsinh  F = Phi(sinh(delta*asinh(y) - eps)), y = (x - loc)/scale
  cauchy        F = 1/2 + atan(y)/pi
and the densities from their formulas (for beta, sinh-arcsinh: also
checked here against mpmath's numerical derivative of F). S = 1 - F is
computed at 50 digits, so tail values are exact to the digits printed.

    python3 tests/dist_reference.py > rows.txt

prints the Fortran rows to paste into test_dist.f95.
D. E. Kittell (with Claude), 10/22/26.
"""
import mpmath as mp
mp.mp.dps = 50

def F(name, p, x):
    x = mp.mpf(x)
    if name == 'uniform':
        return min(max(x, 0), 1)
    if name == 'linear':
        s = p[0]
        return 0 if x <= 0 else (1 if x >= 1 else x + s*(x*x - x))
    if name == 'beta':
        return 0 if x <= 0 else (1 if x >= 1 else
                                 mp.betainc(p[0], p[1], 0, x, regularized=True))
    if name == 'normal':
        return mp.ncdf((x - p[0])/p[1])
    if name == 'split_normal':
        m, sl, sr = p
        if x < m:
            return 2*sl*mp.ncdf((x - m)/sl)/(sl + sr)
        return (sl - sr + 2*sr*mp.ncdf((x - m)/sr))/(sl + sr)
    if name == 'sinh_arcsinh':
        loc, sc, eps, de = p
        y = (x - loc)/sc
        return mp.ncdf(mp.sinh(de*mp.asinh(y) - eps))
    if name == 'cauchy':
        return mp.mpf(1)/2 + mp.atan((x - p[0])/p[1])/mp.pi
    raise ValueError(name)

def f(name, p, x):
    x = mp.mpf(x)
    if name == 'uniform':
        return mp.mpf(1) if 0 <= x <= 1 else mp.mpf(0)
    if name == 'linear':
        return 1 + p[0]*(2*x - 1) if 0 <= x <= 1 else mp.mpf(0)
    if name == 'beta':
        a, b = p
        if x <= 0 or x >= 1:
            return mp.mpf(0)
        return x**(a - 1)*(1 - x)**(b - 1)/mp.beta(a, b)
    if name == 'normal':
        return mp.npdf((x - p[0])/p[1])/p[1]
    if name == 'split_normal':
        m, sl, sr = p
        s = sl if x < m else sr
        return 2*mp.npdf((x - m)/s)/(sl + sr)
    if name == 'sinh_arcsinh':
        loc, sc, eps, de = p
        y = (x - loc)/sc
        w = de*mp.asinh(y) - eps
        return de*mp.cosh(w)*mp.npdf(mp.sinh(w))/(sc*mp.sqrt(1 + y*y))
    if name == 'cauchy':
        y = (x - p[0])/p[1]
        return 1/(mp.pi*p[1]*(1 + y*y))
    raise ValueError(name)

# (name, parameters, x values)
cases = [
    ('uniform', [], [-0.1, 0.3, 1.5]),
    ('linear', [0.5], [0.25, 0.9]),
    ('linear', [-1.0], [0.2]),
    ('linear', [1.0], [0.999]),
    ('beta', [2, 5], [0.1, 0.3, 0.8]),
    ('beta', [0.5, 0.5], [0.01, 0.5, 0.999]),
    ('beta', [0.3, 2], [1e-6, 0.4]),
    ('beta', [50, 60], [0.3, 0.45, 0.6]),
    ('beta', [500, 3], [0.99]),
    ('beta', [2, 1], [0.6]),
    ('normal', [0.5, 0.1], [0.5, 0.6, 0.1, 1.5]),
    ('normal', [-8, 1], [0.0, 1.0]),
    ('split_normal', [0.3, 0.05, 0.2], [0.1, 0.3, 0.5, 1.0]),
    ('sinh_arcsinh', [0.5, 0.2, -0.8, 1.0], [0.0, 0.3, 0.5, 0.9, 1.0]),
    ('sinh_arcsinh', [0.5, 0.2, 0.0, 0.5], [0.9]),
    ('sinh_arcsinh', [0.5, 0.2, 1.5, 2.0], [0.2, 0.7]),
    ('cauchy', [0.5, 0.1], [0.6, -100.0, 0.2]),
    ('cauchy', [0.5, 1e-6], [1.0]),
]

# Means over [0, 1] (the probability on a layer), including tiny ones
# that must come from the accurate tail.
mcases = [
    ('normal', [-8, 1]),
    ('normal', [9, 1]),
    ('cauchy', [50, 0.1]),
    ('sinh_arcsinh', [-2, 0.25, 0.3, 1.2]),
    ('beta', [2, 5]),
]

def num(v):
    v = mp.mpf(v)
    if v == 0:
        return '0.0_wp'
    return mp.nstr(v, 20, min_fixed=0, max_fixed=0).replace('e', 'E') + '_wp'

def given(v):
    # An input exactly as typed (the shortest decimal for the double).
    r = repr(float(v)).replace('e', 'E')
    return r + '_wp'

def pars(p):
    q = list(p) + [0]*(4 - len(p))
    return '(/ ' + ', '.join(given(v) for v in q) + ' /)'

# Check the densities against mpmath's derivative of F (away from kinks).
for name, p, xs in cases:
    for x in xs:
        if name in ('uniform', 'linear', 'beta') and not 0 < x < 1:
            continue
        if name == 'split_normal' and x == p[0]:
            continue
        d = mp.diff(lambda t: F(name, p, t), x, h=mp.mpf(x)*mp.mpf('1e-20') if x else None)
        assert abs(d - f(name, p, x)) <= mp.mpf('1e-15')*max(1, abs(d)), (name, p, x)

rows = []
for name, p, xs in cases:
    for x in xs:
        Fx = F(name, p, x)
        rows.append("   ref_t( '%s', %d, %s, %s, &\n      %s, %s, %s )"
                    % (name, len(p), pars(p), given(x), num(f(name, p, x)),
                       num(Fx), num(1 - Fx)))
print('! %d rows: name, number of parameters, parameters, x, f(x), F(x), S(x)'
      % len(rows))
print(', &\n'.join(rows))
print()
mrows = []
for name, p in mcases:
    mass = F(name, p, 1) - F(name, p, 0)
    mrows.append("   mref_t( '%s', %d, %s, %s )" % (name, len(p), pars(p), num(mass)))
print('! %d rows: name, number of parameters, parameters, mean of f on [0, 1]'
      % len(mrows))
print(', &\n'.join(mrows))
