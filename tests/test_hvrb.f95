program test_hvrb
!**********************************************************************!
!
!  Purpose:
!    Unit test for the burn (module hvrb: the rate law, the topology,
!    the closure) and the ideal-gas products (module products). Run by
!    "make test"; the exit status is 0 if every check passes, 1 if any
!    check fails, so make (and any script) can tell.
!
!  Where the expected values come from:
!    NOT from module hvrb. The "lam" and "mix" tables were computed in
!    Python with 50-digit arithmetic (mpmath) from the definitions in
!    doc/HVRB_Eqns_v8: the topology's closed form; the isentrope from
!    rest by quadrature of the cold-curve integral; the pressure by the
!    sheet's closure (with the solid dropped while it would pull,
!    doc/design/materials.md, phase 3); c**2 and dP/dlam by numerical
!    differentiation of that pressure, not from the closed forms the
!    module uses. Generator: tests/hvrb_reference.py. The other
!    sections check by hand: the rate's threshold for every ZR, the
!    D^2 law against its closed form, the constant-volume burn, the
!    limits (the Hugoniot's reach, a gas with no temperature).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/04/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use, intrinsic :: iso_fortran_env, only: int64
use bits, only: dp, int32, zero, half, one, quit
use eos, only: mg_eos, mg_soundspeed, eos_ok, eos_too_compressed, &
   eos_bad_soundspeed
use products, only: idg_state
use hvrb, only: hvrb_phi_end, hvrb_lambda, hvrb_rate, hvrb_step, &
   hvrb_state, hvrb_c_exact, hvrb_c_mass
implicit none

!**********************************************************************!
! Data dictionary: the two materials of the reference (tests/
! hvrb_reference.py). 1: Material X, the sheet's values (C_V of the
! gold-standard runs); 2: aluminum's Mie-Gruneisen with made-up
! products (a second set of constants, and S2 = 0: a Hugoniot with a
! reach, eta < 1/S1 = 0.746).
!**********************************************************************!
!                                     R0      C0      S1      S2      G0
real(kind=dp), parameter, dimension(5,2) :: mat = reshape( (/ &
                                    1.60_dp, 2.50_dp, 1.80_dp, -0.10_dp, 1.20_dp, &
                                    2.78_dp, 5.30_dp, 1.34_dp,  0.00_dp, 2.00_dp /), &
                                    (/ 5, 2 /) )
!                                     C_V (kJ/(g K))    T0 (K)   gamma    Q (kJ/g)
real(kind=dp), parameter, dimension(4,2) :: brn = reshape( (/ &
                                    1.1633418e-3_dp, 298.0_dp, 2.60_dp, 4.8828_dp, &
                                    0.9e-3_dp,       300.0_dp, 3.0_dp,  2.0_dp /), &
                                    (/ 4, 2 /) )

!**********************************************************************!
! Data dictionary: the reference rows.
!**********************************************************************!
type :: lam_t
   real(kind=dp) :: mr, xr               ! the topology's exponents
   real(kind=dp) :: phi                  ! history variable
   real(kind=dp) :: lam                  ! lam(phi), expected
end type lam_t

type :: mix_t
   integer(kind=int32) :: m              ! material, index into mat, brn
   real(kind=dp) :: rho, e, lam          ! the state
   real(kind=dp) :: es                   ! e_S at rho, kJ/g (input)
   real(kind=dp) :: p, c, theta, dpdlam  ! expected
end type mix_t

! 18 topology rows: MR, XR, phi, lam(phi)
type(lam_t), parameter, dimension(18) :: lams = (/ &
   lam_t( 1.5_dp, 2.5_dp, &
      0.0000000018420157493201933029_dp, &
      0.000000000000079056941504207608300_dp ), &
   lam_t( 1.5_dp, 2.5_dp, &
      0.00018420157493201933029_dp, &
      0.0000024999981250003125000_dp ), &
   lam_t( 1.5_dp, 2.5_dp, &
      0.036840314986403866058_dp, &
      0.0070560748854354109334_dp ), &
   lam_t( 1.5_dp, 2.5_dp, &
      0.55260472479605799087_dp, &
      0.36158332598450563746_dp ), &
   lam_t( 1.5_dp, 2.5_dp, &
      1.2894110245241353120_dp, &
      0.88949374407199846914_dp ), &
   lam_t( 1.5_dp, 2.5_dp, &
      1.8235955918269913699_dp, &
      0.99997261543439575761_dp ), &
   lam_t( 1.0_dp, 1.5_dp, &
      0.0000000015000000000000000000_dp, &
      0.0000000014999999996249999999_dp ), &
   lam_t( 1.0_dp, 1.5_dp, &
      0.00015000000000000000000_dp, &
      0.00014999624993749765613_dp ), &
   lam_t( 1.0_dp, 1.5_dp, &
      0.030000000000000000000_dp, &
      0.029849496212056796522_dp ), &
   lam_t( 1.0_dp, 1.5_dp, &
      0.45000000000000000000_dp, &
      0.41433798142614711642_dp ), &
   lam_t( 1.0_dp, 1.5_dp, &
      1.0500000000000000000_dp, &
      0.83568323274845016596_dp ), &
   lam_t( 1.0_dp, 1.5_dp, &
      1.4850000000000000000_dp, &
      0.99900000000000000000_dp ), &
   lam_t( 0.8_dp, 0.7_dp, &
      0.00000000064028385346008610598_dp, &
      0.000000044167014531626067971_dp ), &
   lam_t( 0.8_dp, 0.7_dp, &
      0.000064028385346008610598_dp, &
      0.00044171195382227485950_dp ), &
   lam_t( 0.8_dp, 0.7_dp, &
      0.012805677069201722120_dp, &
      0.030818876789609584872_dp ), &
   lam_t( 0.8_dp, 0.7_dp, &
      0.19208515603802583179_dp, &
      0.28574984559299103879_dp ), &
   lam_t( 0.8_dp, 0.7_dp, &
      0.44819869742206027419_dp, &
      0.62293876020577792214_dp ), &
   lam_t( 0.8_dp, 0.7_dp, &
      0.63388101492548524492_dp, &
      0.96592247330634290400_dp ) /)

! 64 closure rows: material, rho, e, lam, e_S; then P, c, vartheta, dP/dlam
! (two tables: a statement may continue at most 255 lines)
type(mix_t), parameter, dimension(32) :: mix_a = (/ &
   mix_t( 1, 1.3333333333333333333_dp, &
      0.10905056260177434377_dp, 0.0_dp, &
      0.081755450005121964307_dp, &
      -1.0109932901749636303_dp, &
      1.4901769178896307409_dp, &
      0.30000000000000000000_dp, &
      0.64000000000000000000_dp ), & ! P_sol = -1.011 GPa
   mix_t( 1, 1.3333333333333333333_dp, &
      -1.2985046061787579594_dp, 0.3_dp, &
      0.081755450005121964307_dp, &
      0.19200000000000000000_dp, &
      0.78297018405817397693_dp, &
      0.30000000000000000000_dp, &
      3.6427843600651355800_dp ), & ! solid dropped
   mix_t( 1, 1.3333333333333333333_dp, &
      -3.6444298874796451312_dp, 0.8_dp, &
      0.081755450005121964307_dp, &
      0.51200000000000000000_dp, &
      1.0863805556588322043_dp, &
      0.30000000000000000000_dp, &
      8.6474249601736948800_dp ), & ! solid dropped
   mix_t( 1, 1.3333333333333333333_dp, &
      -4.5828000000000000000_dp, 1.0_dp, &
      0.081755450005121964307_dp, &
      0.64000000000000000000_dp, &
      1.1171392035015152936_dp, &
      0.30000000000000000000_dp, &
      10.649281200217118600_dp ), & ! solid dropped
   mix_t( 1, 1.3333333333333333333_dp, &
      2.8090505626017743438_dp, 0.0_dp, &
      0.081755450005121964307_dp, &
      4.1730067098250363697_dp, &
      2.7963095763185876697_dp, &
      3.0000000000000000000_dp, &
      11.235346370370370370_dp ), & ! P_sol = 4.173 GPa
   mix_t( 1, 1.3333333333333333333_dp, &
      1.4014953938212420406_dp, 0.3_dp, &
      0.081755450005121964307_dp, &
      4.8411046968775254588_dp, &
      3.0333834364662386835_dp, &
      3.0000000000000000000_dp, &
      11.535624806376883928_dp ), & ! P_sol = 4.173 GPa
   mix_t( 1, 1.3333333333333333333_dp, &
      -0.94442988747964513125_dp, 0.8_dp, &
      0.081755450005121964307_dp, &
      5.9546013419650072739_dp, &
      3.3964071383334195106_dp, &
      3.0000000000000000000_dp, &
      12.036088866387739858_dp ), & ! P_sol = 4.173 GPa
   mix_t( 1, 1.3333333333333333333_dp, &
      -1.8828000000000000000_dp, 1.0_dp, &
      0.081755450005121964307_dp, &
      6.4000000000000000000_dp, &
      3.5327043465311387419_dp, &
      3.0000000000000000000_dp, &
      16.409281200217118600_dp ), & ! P_sol = 4.173 GPa
   mix_t( 1, 1.5238095238095238095_dp, &
      -0.019532204024686083900_dp, 0.0_dp, &
      0.0069548221827798990292_dp, &
      -0.47088915491063883168_dp, &
      2.1841468530324367383_dp, &
      0.30000000000000000000_dp, &
      0.73142857142857142857_dp ), & ! P_sol = -0.4709 GPa
   mix_t( 1, 1.5238095238095238095_dp, &
      -1.3885125428172802587_dp, 0.3_dp, &
      0.0069548221827798990292_dp, &
      0.21942857142857142857_dp, &
      0.66630252787888765625_dp, &
      0.30000000000000000000_dp, &
      4.0691330164848010358_dp ), & ! solid dropped
   mix_t( 1, 1.5238095238095238095_dp, &
      -3.6701464408049372168_dp, 0.8_dp, &
      0.0069548221827798990292_dp, &
      0.58514285714285714286_dp, &
      1.0253767005471634588_dp, &
      0.30000000000000000000_dp, &
      9.6319737582451837144_dp ), & ! solid dropped
   mix_t( 1, 1.5238095238095238095_dp, &
      -4.5828000000000000000_dp, 1.0_dp, &
      0.0069548221827798990292_dp, &
      0.73142857142857142857_dp, &
      1.1171392035015152936_dp, &
      0.30000000000000000000_dp, &
      11.857110054949336786_dp ), & ! solid dropped
   mix_t( 1, 1.5238095238095238095_dp, &
      2.6804677959753139161_dp, 0.0_dp, &
      0.0069548221827798990292_dp, &
      4.7131108450893611683_dp, &
      3.0094879091984232141_dp, &
      3.0000000000000000000_dp, &
      11.362649037468955836_dp ), & ! P_sol = 4.713 GPa
   mix_t( 1, 1.5238095238095238095_dp, &
      1.3114874571827197413_dp, 0.3_dp, &
      0.0069548221827798990292_dp, &
      5.4934633058482671035_dp, &
      3.1640297458981082983_dp, &
      3.0000000000000000000_dp, &
      12.071911232043404628_dp ), & ! P_sol = 4.713 GPa
   mix_t( 1, 1.5238095238095238095_dp, &
      -0.97014644080493721678_dp, 0.8_dp, &
      0.0069548221827798990292_dp, &
      6.7940507404464436622_dp, &
      3.4263560082283188457_dp, &
      3.0000000000000000000_dp, &
      13.254014889667485947_dp ), & ! P_sol = 4.713 GPa
   mix_t( 1, 1.5238095238095238095_dp, &
      -1.8828000000000000000_dp, 1.0_dp, &
      0.0069548221827798990292_dp, &
      7.3142857142857142857_dp, &
      3.5327043465311387419_dp, &
      3.0000000000000000000_dp, &
      18.439967197806479643_dp ), & ! P_sol = 4.713 GPa
   mix_t( 1, 1.7777777777777777778_dp, &
      -0.050469292490287553830_dp, 0.0_dp, &
      0.040406644119296199658_dp, &
      1.2969335770157050122_dp, &
      3.2312059865712977923_dp, &
      0.30000000000000000000_dp, &
      8.2584747147362762178_dp ), & ! P_sol = 1.297 GPa
   mix_t( 1, 1.7777777777777777778_dp, &
      -1.4101685047432012877_dp, 0.3_dp, &
      0.040406644119296199658_dp, &
      1.1638535039109935085_dp, &
      2.7687270160414760041_dp, &
      0.30000000000000000000_dp, &
      9.5154410976189698029_dp ), & ! P_sol = 1.297 GPa
   mix_t( 1, 1.7777777777777777778_dp, &
      -3.6763338584980575108_dp, 0.8_dp, &
      0.040406644119296199658_dp, &
      0.94205338206980766911_dp, &
      1.7531569312331508384_dp, &
      0.30000000000000000000_dp, &
      11.610385069090125778_dp ), & ! P_sol = 1.297 GPa
   mix_t( 1, 1.7777777777777777778_dp, &
      -4.5828000000000000000_dp, 1.0_dp, &
      0.040406644119296199658_dp, &
      0.85333333333333333333_dp, &
      1.1171392035015152936_dp, &
      0.30000000000000000000_dp, &
      13.745296234694293180_dp ), & ! P_sol = 1.297 GPa
   mix_t( 1, 1.7777777777777777778_dp, &
      2.6495307075097124462_dp, 0.0_dp, &
      0.040406644119296199658_dp, &
      6.4809335770157050122_dp, &
      3.6864579378658579629_dp, &
      3.0000000000000000000_dp, &
      10.754474714736276218_dp ), & ! P_sol = 6.481 GPa
   mix_t( 1, 1.7777777777777777778_dp, &
      1.2898314952567987123_dp, 0.3_dp, &
      0.040406644119296199658_dp, &
      7.0966535039109935085_dp, &
      3.6175445386833782177_dp, &
      3.0000000000000000000_dp, &
      12.011441097618969803_dp ), & ! P_sol = 6.481 GPa
   mix_t( 1, 1.7777777777777777778_dp, &
      -0.97633385849805751077_dp, 0.8_dp, &
      0.040406644119296199658_dp, &
      8.1228533820698076691_dp, &
      3.5457301681784583843_dp, &
      3.0000000000000000000_dp, &
      14.106385069090125778_dp ), & ! P_sol = 6.481 GPa
   mix_t( 1, 1.7777777777777777778_dp, &
      -1.8828000000000000000_dp, 1.0_dp, &
      0.040406644119296199658_dp, &
      8.5333333333333333333_dp, &
      3.5327043465311387419_dp, &
      3.0000000000000000000_dp, &
      21.425296234694293180_dp ), & ! P_sol = 6.481 GPa
   mix_t( 1, 2.1333333333333333333_dp, &
      0.23692865222740800903_dp, 0.0_dp, &
      0.40489211036290169319_dp, &
      7.2035926020980381728_dp, &
      5.0040898227335064599_dp, &
      0.30000000000000000000_dp, &
      3.0742864101785852045_dp ), & ! P_sol = 7.204 GPa
   mix_t( 1, 2.1333333333333333333_dp, &
      -1.2089899434408143937_dp, 0.3_dp, &
      0.40489211036290169319_dp, &
      5.3497148214686267210_dp, &
      4.2275489905842060240_dp, &
      0.30000000000000000000_dp, &
      5.2335248463764639925_dp ), & ! P_sol = 7.204 GPa
   mix_t( 1, 2.1333333333333333333_dp, &
      -3.6188542695545183982_dp, 0.8_dp, &
      0.40489211036290169319_dp, &
      2.2599185204196076346_dp, &
      2.4460300469939062507_dp, &
      0.30000000000000000000_dp, &
      8.8322555733729286393_dp ), & ! P_sol = 7.204 GPa
   mix_t( 1, 2.1333333333333333333_dp, &
      -4.5828000000000000000_dp, 1.0_dp, &
      0.40489211036290169319_dp, &
      1.0240000000000000000_dp, &
      1.1171392035015152936_dp, &
      0.30000000000000000000_dp, &
      17.475340466269552671_dp ), & ! P_sol = 7.204 GPa
   mix_t( 1, 2.1333333333333333333_dp, &
      2.9369286522274080090_dp, 0.0_dp, &
      0.40489211036290169319_dp, &
      12.387592602098038173_dp, &
      5.2180374619185186629_dp, &
      3.0000000000000000000_dp, &
      7.1062864101785852045_dp ), & ! P_sol = 12.39 GPa
   mix_t( 1, 2.1333333333333333333_dp, &
      1.4910100565591856063_dp, 0.3_dp, &
      0.40489211036290169319_dp, &
      11.743314821468626721_dp, &
      4.7428725966221714729_dp, &
      3.0000000000000000000_dp, &
      9.2655248463764639925_dp ), & ! P_sol = 12.39 GPa
   mix_t( 1, 2.1333333333333333333_dp, &
      -0.91885426955451839819_dp, 0.8_dp, &
      0.40489211036290169319_dp, &
      10.669518520419607635_dp, &
      3.8979973051295214077_dp, &
      3.0000000000000000000_dp, &
      12.864255573372928639_dp ), & ! P_sol = 12.39 GPa
   mix_t( 1, 2.1333333333333333333_dp, &
      -1.8828000000000000000_dp, 1.0_dp, &
      0.40489211036290169319_dp, &
      10.240000000000000000_dp, &
      3.5327043465311387419_dp, &
      3.0000000000000000000_dp, &
      26.691340466269552671_dp ) /) ! P_sol = 12.39 GPa
type(mix_t), parameter, dimension(32) :: mix_b = (/ &
   mix_t( 2, 2.3166666666666666667_dp, &
      0.52122551896488182298_dp, 0.0_dp, &
      0.40221193139450443418_dp, &
      -8.7673604912219237309_dp, &
      3.6676969834721969073_dp, &
      0.30000000000000000000_dp, &
      1.3900000000000000000_dp ), & ! P_sol = -8.767 GPa
   mix_t( 2, 2.3166666666666666667_dp, &
      -0.14514213672458272391_dp, 0.3_dp, &
      0.40221193139450443418_dp, &
      0.41700000000000000000_dp, &
      1.4764410942815832917_dp, &
      0.30000000000000000000_dp, &
      4.4775034713611857339_dp ), & ! solid dropped
   mix_t( 2, 2.3166666666666666667_dp, &
      -1.2557548962070236354_dp, 0.8_dp, &
      0.40221193139450443418_dp, &
      1.1120000000000000000_dp, &
      1.6399485020679676086_dp, &
      0.30000000000000000000_dp, &
      9.6233425902964952905_dp ), & ! solid dropped
   mix_t( 2, 2.3166666666666666667_dp, &
      -1.7000000000000000000_dp, 1.0_dp, &
      0.40221193139450443418_dp, &
      1.3900000000000000000_dp, &
      1.3416407864998738178_dp, &
      0.30000000000000000000_dp, &
      11.681678237870619113_dp ), & ! solid dropped
   mix_t( 2, 2.3166666666666666667_dp, &
      3.2212255189648818230_dp, 0.0_dp, &
      0.40221193139450443418_dp, &
      6.2446395087780762691_dp, &
      5.3855362929397340228_dp, &
      3.0000000000000000000_dp, &
      20.005374376666666667_dp ), & ! P_sol = 6.245 GPa
   mix_t( 2, 2.3166666666666666667_dp, &
      2.5548578632754172761_dp, 0.3_dp, &
      0.40221193139450443418_dp, &
      8.5412476561446533884_dp, &
      5.0598419751806218680_dp, &
      3.0000000000000000000_dp, &
      19.387873682394429520_dp ), & ! P_sol = 6.245 GPa
   mix_t( 2, 2.3166666666666666667_dp, &
      1.4442451037929763646_dp, 0.8_dp, &
      0.40221193139450443418_dp, &
      12.368927901755615254_dp, &
      4.4859781801201631042_dp, &
      3.0000000000000000000_dp, &
      18.358705858607367609_dp ), & ! P_sol = 6.245 GPa
   mix_t( 2, 2.3166666666666666667_dp, &
      1.0000000000000000000_dp, 1.0_dp, &
      0.40221193139450443418_dp, &
      13.900000000000000000_dp, &
      4.2426406871192851464_dp, &
      3.0000000000000000000_dp, &
      24.191678237870619113_dp ), & ! P_sol = 6.245 GPa
   mix_t( 2, 2.6476190476190476190_dp, &
      0.087856371279232874554_dp, 0.0_dp, &
      0.032162474148941959308_dp, &
      -3.1126126071484305560_dp, &
      4.8855184710057842425_dp, &
      0.30000000000000000000_dp, &
      1.5885714285714285714_dp ), & ! P_sol = -3.113 GPa
   mix_t( 2, 2.6476190476190476190_dp, &
      -0.44850054010453698781_dp, 0.3_dp, &
      0.032162474148941959308_dp, &
      0.47657142857142857143_dp, &
      1.0229190421619058365_dp, &
      0.30000000000000000000_dp, &
      4.4287089783750099379_dp ), & ! solid dropped
   mix_t( 2, 2.6476190476190476190_dp, &
      -1.3424287257441534251_dp, 0.8_dp, &
      0.032162474148941959308_dp, &
      1.2708571428571428571_dp, &
      1.3512219138366311655_dp, &
      0.30000000000000000000_dp, &
      9.1622715613809788819_dp ), & ! solid dropped
   mix_t( 2, 2.6476190476190476190_dp, &
      -1.7000000000000000000_dp, 1.0_dp, &
      0.032162474148941959308_dp, &
      1.5885714285714285714_dp, &
      1.3416407864998738178_dp, &
      0.30000000000000000000_dp, &
      11.055696594583366460_dp ), & ! solid dropped
   mix_t( 2, 2.6476190476190476190_dp, &
      2.7878563712792328746_dp, 0.0_dp, &
      0.032162474148941959308_dp, &
      11.899387392851569444_dp, &
      5.9812449147764126553_dp, &
      3.0000000000000000000_dp, &
      13.926808317175251053_dp ), & ! P_sol = 11.9 GPa
   mix_t( 2, 2.6476190476190476190_dp, &
      2.2514994598954630122_dp, 0.3_dp, &
      0.032162474148941959308_dp, &
      13.095285460710384325_dp, &
      5.5169197484988928486_dp, &
      3.0000000000000000000_dp, &
      13.784801439685071984_dp ), & ! P_sol = 11.9 GPa
   mix_t( 2, 2.6476190476190476190_dp, &
      1.3575712742558465749_dp, 0.8_dp, &
      0.032162474148941959308_dp, &
      15.088448907141742460_dp, &
      4.6422255595896823223_dp, &
      3.0000000000000000000_dp, &
      13.548123310534773537_dp ), & ! P_sol = 11.9 GPa
   mix_t( 2, 2.6476190476190476190_dp, &
      1.0000000000000000000_dp, 1.0_dp, &
      0.032162474148941959308_dp, &
      15.885714285714285714_dp, &
      4.2426406871192851464_dp, &
      3.0000000000000000000_dp, &
      25.352839451726223602_dp ), & ! P_sol = 11.9 GPa
   mix_t( 2, 3.0888888888888888889_dp, &
      0.13933325783990390368_dp, 0.0_dp, &
      0.16911200254314975884_dp, &
      10.146066700852051753_dp, &
      6.2156022699961803953_dp, &
      0.30000000000000000000_dp, &
      1.9339595460711472851_dp ), & ! P_sol = 10.15 GPa
   mix_t( 2, 3.0888888888888888889_dp, &
      -0.41246671951206726742_dp, 0.3_dp, &
      0.16911200254314975884_dp, &
      7.6582466905964362269_dp, &
      5.2517690452977051520_dp, &
      0.30000000000000000000_dp, &
      2.2748493098574761419_dp ), & ! P_sol = 10.15 GPa
   mix_t( 2, 3.0888888888888888889_dp, &
      -1.3321333484320192193_dp, 0.8_dp, &
      0.16911200254314975884_dp, &
      3.5118800068370770172_dp, &
      3.0273457542468343110_dp, &
      0.30000000000000000000_dp, &
      2.8429989161680242366_dp ), & ! P_sol = 10.15 GPa
   mix_t( 2, 3.0888888888888888889_dp, &
      -1.7000000000000000000_dp, 1.0_dp, &
      0.16911200254314975884_dp, &
      1.8533333333333333333_dp, &
      1.3416407864998738178_dp, &
      0.30000000000000000000_dp, &
      13.216325459544295227_dp ), & ! P_sol = 10.15 GPa
   mix_t( 2, 3.0888888888888888889_dp, &
      2.8393332578399039037_dp, 0.0_dp, &
      0.16911200254314975884_dp, &
      25.158066700852051753_dp, &
      6.8834374827393958552_dp, &
      3.0000000000000000000_dp, &
      3.6019595460711472851_dp ), & ! P_sol = 25.16 GPa
   mix_t( 2, 3.0888888888888888889_dp, &
      2.2875332804879327326_dp, 0.3_dp, &
      0.16911200254314975884_dp, &
      23.170646690596436227_dp, &
      6.2082202043055116997_dp, &
      3.0000000000000000000_dp, &
      3.9428493098574761419_dp ), & ! P_sol = 25.16 GPa
   mix_t( 2, 3.0888888888888888889_dp, &
      1.3678666515679807807_dp, 0.8_dp, &
      0.16911200254314975884_dp, &
      19.858280006837077017_dp, &
      4.8843773723737127028_dp, &
      3.0000000000000000000_dp, &
      4.5109989161680242366_dp ), & ! P_sol = 25.16 GPa
   mix_t( 2, 3.0888888888888888889_dp, &
      1.0000000000000000000_dp, 1.0_dp, &
      0.16911200254314975884_dp, &
      18.533333333333333333_dp, &
      4.2426406871192851464_dp, &
      3.0000000000000000000_dp, &
      29.896325459544295227_dp ), & ! P_sol = 25.16 GPa
   mix_t( 2, 3.7066666666666666667_dp, &
      1.2985561615484364401_dp, 0.0_dp, &
      1.4437109046374710397_dp, &
      40.329616669990639639_dp, &
      7.8220337854056587847_dp, &
      0.30000000000000000000_dp, &
      -21.433644411781333032_dp ), & ! P_sol = 40.33 GPa
   mix_t( 2, 3.7066666666666666667_dp, &
      0.39898931308390550807_dp, 0.3_dp, &
      1.4437109046374710397_dp, &
      28.897931668993447747_dp, &
      6.5843146019930810840_dp, &
      0.30000000000000000000_dp, &
      -19.766447185960402371_dp ), & ! P_sol = 40.33 GPa
   mix_t( 2, 3.7066666666666666667_dp, &
      -1.1002887676903127120_dp, 0.8_dp, &
      1.4437109046374710397_dp, &
      9.8451233339981279278_dp, &
      3.6965987756322048445_dp, &
      0.30000000000000000000_dp, &
      -16.987785142925517937_dp ), & ! P_sol = 40.33 GPa
   mix_t( 2, 3.7066666666666666667_dp, &
      -1.7000000000000000000_dp, 1.0_dp, &
      1.4437109046374710397_dp, &
      2.2240000000000000000_dp, &
      1.3416407864998738178_dp, &
      0.30000000000000000000_dp, &
      24.453296344279075476_dp ), & ! P_sol = 40.33 GPa
   mix_t( 2, 3.7066666666666666667_dp, &
      3.9985561615484364401_dp, 0.0_dp, &
      1.4437109046374710397_dp, &
      55.341616669990639639_dp, &
      8.2011714126719470528_dp, &
      3.0000000000000000000_dp, &
      -16.429644411781333032_dp ), & ! P_sol = 55.34 GPa
   mix_t( 2, 3.7066666666666666667_dp, &
      3.0989893130839055081_dp, 0.3_dp, &
      1.4437109046374710397_dp, &
      45.411131668993447747_dp, &
      7.2335294827642270255_dp, &
      3.0000000000000000000_dp, &
      -14.762447185960402371_dp ), & ! P_sol = 55.34 GPa
   mix_t( 2, 3.7066666666666666667_dp, &
      1.5997112323096872880_dp, 0.8_dp, &
      1.4437109046374710397_dp, &
      28.860323333998127928_dp, &
      5.2661031615422723252_dp, &
      3.0000000000000000000_dp, &
      -11.983785142925517937_dp ), & ! P_sol = 55.34 GPa
   mix_t( 2, 3.7066666666666666667_dp, &
      1.0000000000000000000_dp, 1.0_dp, &
      1.4437109046374710397_dp, &
      22.240000000000000000_dp, &
      4.2426406871192851464_dp, &
      3.0000000000000000000_dp, &
      44.469296344279075476_dp ) /) ! P_sol = 55.34 GPa
type(mix_t), parameter, dimension(64) :: mix = (/ mix_a, mix_b /)

!*** Tolerances. lam: relative, 1e-13 (the series keeps the precision of
!*** a tiny lam; the direct form is used only where 1 - x keeps it).
!*** The closure: relative to the larger of the value and its scale
!*** (1 GPa, 1 km/s, 1 kJ/g), 1e-12: the inputs are 20-digit decimals,
!*** and P, c**2 and dP/dlam are differences of terms of order 10 to 100
!*** GPa, so a few 1e-14 is round-off; a wrong term, weight or sign is
!*** off by far more.
real(kind=dp), parameter :: ltol = 1.0e-13_dp
real(kind=dp), parameter :: rtol = 1.0e-12_dp

!**********************************************************************!
! Data dictionary: work variables.
!**********************************************************************!
integer(kind=int32) :: i, m, n, ierr, ifb, nfail, ncheck, nbad
real(kind=dp) :: p, c, th, dpl, worst, w(4), phi, lam, t, dt, pend
real(kind=dp) :: pm, cm, x
real(kind=dp), dimension(size(mix)) :: pa, ca, tha, dpla
integer(kind=int32), dimension(size(mix)) :: ifba, ierra
logical :: ok

nfail  = 0
ncheck = 0
write(*,'(a)') ' test_hvrb: the rate law, the topology and the closure'

!=====================================================================!
! 1. The topology against 50 digits: three (MR, XR) pairs (the
!    sheet's, the D^2 law's, both below 1), phi from 1e-9 of phi_end
!    (where the series must keep lam's precision) to 0.99 of it.
!=====================================================================!
worst = zero
do i = 1, size(lams)
   lam = hvrb_lambda( lams(i)%phi, lams(i)%mr, lams(i)%xr )
   worst = max( worst, abs(lam - lams(i)%lam)/lams(i)%lam )
end do
call check( worst <= ltol, itoa(size(lams))//' values of lam(phi) to '// &
   'within '//rtoa(worst)//' (relative)' )

!=====================================================================!
! 2. The topology's ends: lam(0) = 0, lam(phi_end) = 1 exactly, and 1
!    beyond; a step never takes phi past phi_end, and lands on it.
!=====================================================================!
ok = .true.
do i = 1, size(lams)
   pend = hvrb_phi_end( lams(i)%mr, lams(i)%xr )
   if ( abs( hvrb_lambda( zero, lams(i)%mr, lams(i)%xr ) ) > zero ) ok = .false.
   if ( abs( hvrb_lambda( pend, lams(i)%mr, lams(i)%xr ) - one ) > zero ) &
      ok = .false.
   if ( abs( hvrb_lambda( 2*pend, lams(i)%mr, lams(i)%xr ) - one ) > zero ) &
      ok = .false.
   call hvrb_step( half*pend, 100.0_dp, 10.0_dp, 7.0_dp, 3.0_dp, &
      lams(i)%mr, lams(i)%xr, 1.0_dp, 1.0_dp, phi, lam )
   if ( abs(phi - pend) > zero .or. abs(lam - one) > zero ) ok = .false.
end do
call check( ok, 'lam(0) = 0, lam = 1 exactly from phi_end on; a step '// &
   'stops at phi_end, lam = 1' )

!=====================================================================!
! 3. The rate: 0 at and below the threshold for every ZR (0 included:
!    no 0**0), at rest with PI = 0 and in tension; ZR = 0 is 1/TAU0
!    above it, whatever PR; ZR = 3 by hand, ((15 - 1)/7)**3/2 = 4.
!=====================================================================!
ok = .true.
do i = 0, 3
   x = real(i, dp)                                     ! ZR = 0, 1, 2, 3
   if ( abs( hvrb_rate( 1.0_dp, 7.0_dp, x, 1.0_dp, 1.0_dp ) ) > zero ) &
      ok = .false.                                     ! P = PI
   if ( abs( hvrb_rate( 0.5_dp, 7.0_dp, x, 1.0_dp, 1.0_dp ) ) > zero ) &
      ok = .false.                                     ! P < PI
   if ( abs( hvrb_rate( zero, 7.0_dp, x, zero, 1.0_dp ) ) > zero ) &
      ok = .false.                                     ! at rest, PI = 0
   if ( abs( hvrb_rate( -3.0_dp, 7.0_dp, x, zero, 1.0_dp ) ) > zero ) &
      ok = .false.                                     ! tension
end do
if ( abs( hvrb_rate( 5.0_dp, 7.0_dp, zero, 1.0_dp, 0.25_dp ) - 4.0_dp ) &
   > zero ) ok = .false.
if ( abs( hvrb_rate( 5.0_dp, 1.0e6_dp, zero, 1.0_dp, 0.25_dp ) - 4.0_dp ) &
   > zero ) ok = .false.
if ( abs( hvrb_rate( 15.0_dp, 7.0_dp, 3.0_dp, 1.0_dp, 2.0_dp ) - 4.0_dp ) &
   > 4.0_dp*epsilon(one) ) ok = .false.
call check( ok, 'rate: 0 at or below PI for ZR = 0 to 3 (at rest, in '// &
   'tension); ZR = 0 is 1/TAU0; ZR = 3 by hand' )

!=====================================================================!
! 4. A burn on a clock: ZR = 0, MR = 1, XR = 1.5 is the D^2 law,
!    lam(t) = 1 - (1 - t/t_b)**1.5 with t_b = 1.5 TAU0, while the
!    cell stays above PI. Step by step (dt = 0.001 us, TAU0 = 0.4 us,
!    t_b = 0.6 us, 650 steps: past burn-out), against the closed form.
!=====================================================================!
phi = zero
t   = zero
dt  = 1.0e-3_dp
worst = zero
do n = 1, 650
   call hvrb_step( phi, 5.0_dp, dt, 7.0_dp, zero, one, 1.5_dp, 1.0_dp, &
      0.4_dp, x, lam )
   phi = x
   t = real(n, dp)*dt
   x = one - min( t/0.6_dp, one )
   worst = max( worst, abs( lam - ( one - x*sqrt(x) ) ) )
end do
call check( worst <= 1.0e-13_dp .and. abs(lam - one) <= zero, &
   'ZR = 0, MR = 1, XR = 1.5: the D^2 law, 650 steps, to within '// &
   rtoa(worst)//'; burnt out' )

!=====================================================================!
! 5. The closure against 50 digits: P, c, vartheta and dP/dlam at
!    every reference state (two materials, tension and compression,
!    lam = 0, 0.3, 0.8, 1; the solid dropped in 12 of them).
!=====================================================================!
w = zero
nbad = 0
do i = 1, size(mix)
   m = mix(i)%m
   call hvrb_state( mix(i)%rho, mix(i)%e, mix(i)%lam, mix(i)%es, &
      mat(1,m), mat(2,m), mat(3,m), mat(4,m), mat(5,m), brn(1,m), &
      brn(2,m), brn(3,m), brn(4,m), p, c, th, dpl, ifb, ierr )
   if ( ierr /= eos_ok .or. ifb /= hvrb_c_exact ) then
      nbad = nbad + 1
      cycle
   end if
   w(1) = max( w(1), abs(p   - mix(i)%p     )/max( abs(mix(i)%p), one ) )
   w(2) = max( w(2), abs(c   - mix(i)%c     )/max( abs(mix(i)%c), one ) )
   w(3) = max( w(3), abs(th  - mix(i)%theta )/max( abs(mix(i)%theta), one ) )
   w(4) = max( w(4), abs(dpl - mix(i)%dpdlam)/max( abs(mix(i)%dpdlam), one ) )
end do
call check( nbad == 0 .and. maxval(w) <= rtol, itoa(size(mix))// &
   ' closure states (P, c, vartheta, dP/dlam) to within '// &
   rtoa(maxval(w))//', all by the exact sound speed' )

!=====================================================================!
! 6. Unburnt is the inert material, bit for bit: at lam = 0, P and c
!    are mg_eos's own (the eos = mie_gruneisen_t cell's).
!=====================================================================!
ok = .true.
do i = 1, size(mix)
   if ( mix(i)%lam > zero ) cycle
   m = mix(i)%m
   call hvrb_state( mix(i)%rho, mix(i)%e, zero, mix(i)%es, mat(1,m), &
      mat(2,m), mat(3,m), mat(4,m), mat(5,m), brn(1,m), brn(2,m), &
      brn(3,m), brn(4,m), p, c, th, dpl, ifb, ierr )
   call mg_eos( mix(i)%rho, mix(i)%e, mat(1,m), mat(2,m), mat(3,m), &
      mat(4,m), mat(5,m), pm, cm, n )
   if ( ierr /= n .or. .not. ( same(p, pm) .and. same(c, cm) ) ) ok = .false.
end do
call check( ok, 'lam = 0: P and c are mg_eos''s, bit for bit' )

!=====================================================================!
! 7. The constant-volume burn (the sheet's check): at rest, e = 0,
!    burnt out, P = (gamma - 1) R0 Q = 1.6*1.6*4.8828 = 12.499968 GPa;
!    and vartheta = Q there (T = Q/C_V).
!=====================================================================!
call hvrb_state( mat(1,1), zero, one, zero, mat(1,1), mat(2,1), mat(3,1), &
   mat(4,1), mat(5,1), brn(1,1), brn(2,1), brn(3,1), brn(4,1), p, c, th, &
   dpl, ifb, ierr )
call check( ierr == eos_ok .and. abs(p - 12.499968_dp) <= 1.0e-13_dp*p &
   .and. abs(th - 4.8828_dp) <= 1.0e-15_dp*th, &
   'constant-volume burn ends at 12.499968 GPa, vartheta = Q' )

!=====================================================================!
! 8. The Hugoniot's reach (aluminum: eta < 1/S1 = 0.746). At eta =
!    0.75, a cell at lam = 0.5 stops (eos_too_compressed, as an inert
!    cell does); burnt out, the solid is not evaluated and the gas
!    gives P = (gamma - 1) rho vartheta.
!=====================================================================!
x = mat(1,2)/( one - 0.75_dp )                         ! rho at eta = 0.75
call hvrb_state( x, 5.0_dp, half, 3.0_dp, mat(1,2), mat(2,2), mat(3,2), &
   mat(4,2), mat(5,2), brn(1,2), brn(2,2), brn(3,2), brn(4,2), p, c, th, &
   dpl, ifb, ierr )
ok = ierr == eos_too_compressed
call hvrb_state( x, 5.0_dp, one, 3.0_dp, mat(1,2), mat(2,2), mat(3,2), &
   mat(4,2), mat(5,2), brn(1,2), brn(2,2), brn(3,2), brn(4,2), p, c, th, &
   dpl, ifb, ierr )
ok = ok .and. ierr == eos_ok .and. &
   abs( p - ( brn(3,2) - one )*x*( 5.0_dp + brn(4,2) ) ) <= 1.0e-14_dp*p
call check( ok, 'past the reach: lam = 0.5 stops the run; lam = 1 '// &
   'never evaluates the solid' )

!=====================================================================!
! 9. The guards. A burnt cell with no temperature (vartheta = 0: e =
!    -Q at rest): no pressure, no sound speed, eos_bad_soundspeed. A
!    half-burnt cell at rest with vartheta < 0 (the solid would pull):
!    no gas pressure, so the exact rule gives c**2 = 0, and the
!    mass-weighted one takes over, c**2 = (1/2) c_sol**2 at P = 0,
!    which at rest is C0**2/2.
!=====================================================================!
call hvrb_state( mat(1,1), -brn(4,1), one, zero, mat(1,1), mat(2,1), &
   mat(3,1), mat(4,1), mat(5,1), brn(1,1), brn(2,1), brn(3,1), brn(4,1), &
   p, c, th, dpl, ifb, ierr )
ok = ierr == eos_bad_soundspeed .and. abs(th) <= 1.0e-15_dp
x = -brn(1,1)*brn(2,1)                                 ! ecs at rest
call hvrb_state( mat(1,1), half*x - half*brn(4,1) - 0.01_dp, half, zero, &
   mat(1,1), mat(2,1), mat(3,1), mat(4,1), mat(5,1), brn(1,1), brn(2,1), &
   brn(3,1), brn(4,1), p, c, th, dpl, ifb, ierr )
call mg_soundspeed( mat(1,1), zero, mat(1,1), mat(2,1), mat(3,1), &
   mat(4,1), mat(5,1), cm, n )
ok = ok .and. ierr == eos_ok .and. ifb == hvrb_c_mass .and. th < zero &
   .and. abs(p) <= zero .and. abs( c - sqrt(half)*cm ) <= 1.0e-14_dp*c
call check( ok, 'guards: vartheta = 0 burnt out has no sound speed; '// &
   'vartheta < 0 half burnt falls back to the mass-weighted c' )

!=====================================================================!
! 10. The ideal gas by hand: P = (gamma-1) rho vartheta, c**2 =
!     gamma (gamma-1) vartheta; nothing at vartheta <= 0.
!=====================================================================!
call idg_state( 2.0_dp, 3.0_dp, 2.5_dp, p, x )
ok = abs(p - 9.0_dp) <= 9.0_dp*epsilon(one) .and. &
   abs(x - 11.25_dp) <= 11.25_dp*epsilon(one)
call idg_state( 2.0_dp, -1.0_dp, 2.5_dp, p, x )
ok = ok .and. abs(p) <= zero .and. abs(x) <= zero
call check( ok, 'ideal gas by hand; no pressure at vartheta <= 0' )

!=====================================================================!
! 11. Elemental: the whole table in one call gives the same bits as one
!     call per state.
!=====================================================================!
call hvrb_state( mix%rho, mix%e, mix%lam, mix%es, mat(1,mix%m), &
   mat(2,mix%m), mat(3,mix%m), mat(4,mix%m), mat(5,mix%m), brn(1,mix%m), &
   brn(2,mix%m), brn(3,mix%m), brn(4,mix%m), pa, ca, tha, dpla, ifba, ierra )
ok = .true.
do i = 1, size(mix)
   m = mix(i)%m
   call hvrb_state( mix(i)%rho, mix(i)%e, mix(i)%lam, mix(i)%es, &
      mat(1,m), mat(2,m), mat(3,m), mat(4,m), mat(5,m), brn(1,m), &
      brn(2,m), brn(3,m), brn(4,m), p, c, th, dpl, ifb, ierr )
   if ( .not. ( same(p, pa(i)) .and. same(c, ca(i)) .and. same(th, tha(i)) &
      .and. same(dpl, dpla(i)) ) .or. ifb /= ifba(i) .or. ierr /= ierra(i) ) &
      ok = .false.
end do
call check( ok, 'array (elemental) call == one call per state' )

!=====================================================================!
! Summary. Exit status 1 on any failure, so 'make test' stops.
!=====================================================================!
if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_hvrb: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_hvrb: all ', ncheck, ' checks passed'

contains

   !*** Count one check, and print it.
   subroutine check( okk, what )
   implicit none
   logical, intent(in) :: okk
   character(len=*), intent(in) :: what
   ncheck = ncheck + 1
   if ( okk ) then
      write(*,'(a)') '   pass  '//what
   else
      write(*,'(a)') '   FAIL  '//what
      nfail = nfail + 1
   end if
   end subroutine check

   !*** The same bits (a bit-for-bit check, without comparing reals).
   logical function same( a, b )
   implicit none
   real(kind=dp), intent(in) :: a, b
   same = transfer( a, 0_int64 ) == transfer( b, 0_int64 )
   end function same

   !*** An integer as text, without padding.
   function itoa( k ) result(s)
   implicit none
   integer(kind=int32), intent(in) :: k
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(i0)' ) k
   s = trim(buf)
   end function itoa

   !*** A small real as text, e.g. 3.1E-14.
   function rtoa( r ) result(s)
   implicit none
   real(kind=dp), intent(in) :: r
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(es8.1)' ) r
   s = trim(adjustl(buf))
   end function rtoa

end program test_hvrb
