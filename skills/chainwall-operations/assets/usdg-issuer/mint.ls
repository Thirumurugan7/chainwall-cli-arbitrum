{
  $require($subjectPolicy == {{issuancePolicyId}}),
  $require($subjectVault == {{vault}}),
  $require($subjectNativeValue == 0),
  $require($subjectArgCount == 2),
  $require($arg1 > 0),
  @contract({{org}}/usdg).mint($arg0 :: address, $arg1 :: uint256)
}
