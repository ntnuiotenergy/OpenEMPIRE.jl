"""
Numerical tests for the annuity (capital recovery) factor.

InternalEMPIRE corrected the exponent from `1 - lifetime` to `-lifetime` in
b3186227 ("Fix WACC calculation to recover the capital cost over lifetime"), so the
factor is now the textbook present value of `life` annual payments of 1. These tests
pin the corrected convention against closed-form values and guard against a silent
return of the old one.
"""
function test_annuity_factor()
    # a_n = (1 - (1+w)^-n) / w, computed independently of the implementation.
    closed_form(wacc, life) = (1 - (1 + wacc)^(-life)) / wacc

    for (wacc, life) in ((0.05, 10), (0.05, 40), (0.05, 20), (0.05, 25), (0.07, 30))
        @test OpenEMPIRE.annuity_factor(wacc, life) ≈ closed_form(wacc, life)
    end

    # Representative lifetimes, to 10 significant digits.
    @test OpenEMPIRE.annuity_factor(0.05, 10) ≈ 7.721734929 atol = 1e-9
    @test OpenEMPIRE.annuity_factor(0.05, 40) ≈ 17.15908635 atol = 1e-8

    # The superseded `1 - life` convention must not come back. It spreads capital over
    # one payment fewer, so it is strictly smaller and the annual charge strictly
    # larger: +8.6% at a 10-year lifetime, +0.8% at 40 years.
    for life in (10, 40)
        superseded = (1 - (1 + 0.05)^(1 - life)) / 0.05
        @test !isapprox(OpenEMPIRE.annuity_factor(0.05, life), superseded; atol = 1e-9)
        @test OpenEMPIRE.annuity_factor(0.05, life) > superseded
    end

    # An annual charge is capital / a_n; check the ratio the model actually applies.
    @test 1 / OpenEMPIRE.annuity_factor(0.05, 10) ≈ 0.1295045750 atol = 1e-9

    # A one-year asset recovers exactly its capital discounted one period.
    @test OpenEMPIRE.annuity_factor(0.05, 1) ≈ 1 / 1.05 atol = 1e-12

    return nothing
end
