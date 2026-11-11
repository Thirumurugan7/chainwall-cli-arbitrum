{
  $require($subjectPolicy == {{compliancePolicyId}}),
  $require($subjectVault == {{vault}}),
  $require($subjectId == {{burnId}} || $subjectId == {{freezeId}} || $subjectId == {{unfreezeId}} || $subjectId == {{wipeId}}),
  $require($subjectNativeValue == 0),
  $require($subjectArgCount == 1)
}
