{
  $require($subjectPolicy == {{compliancePolicyId}}),
  $require($subjectVault == {{vault}}),
  $require($subjectNativeValue == 0),
  $require($subjectArgCount == 1),
  $require($arg0 > 0),
  @contract({{org}}/usdg).burn($arg0 :: uint256)
}
