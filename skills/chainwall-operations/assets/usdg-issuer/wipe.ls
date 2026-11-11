{
  $require($subjectPolicy == {{compliancePolicyId}}),
  $require($subjectVault == {{vault}}),
  $require($subjectNativeValue == 0),
  $require($subjectArgCount == 1),
  @contract({{org}}/usdg).wipeFrozenAddress($arg0 :: address)
}
