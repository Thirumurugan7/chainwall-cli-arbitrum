{
  $require($subjectPolicy == {{compliancePolicyId}}),
  $require($subjectVault == {{vault}}),
  $require($subjectNativeValue == 0),
  $require($subjectArgCount == 1),
  @contract({{org}}/usdg).freeze($arg0 :: address)
}
