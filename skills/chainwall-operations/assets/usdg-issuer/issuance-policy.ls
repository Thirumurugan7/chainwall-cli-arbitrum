{
  $require(($subjectPolicy == {{issuancePolicyId}})),
  {
    $require(($subjectVault == {{vaultWord}})),
    {
      $require(($address({{coinKey}}) == {{coinWord}})),
      {
        $require(($subjectNativeValue == 0)),
        {
          $require(($subjectId == {{mintId}})),
          {
            $require(($subjectArgCount == 2)),
            {
              let $shared12 = $subjectArg(1),
              {
                $require(IF(($shared12 > 0),
                ($shared12 <= {{mintCap}}),
                false)),
                {
                  let $shared16 = $read({{coinKey}},
                  404098525),
                  {
                    let $shared18 = $read({{registryWord}},
                    83875018,
                    {
                      $subjectPolicy,
                      {{limitsNamespace}},
                      {{vaultWord}},
                      {{capKey}}
                    }),
                    {
                      $require(($shared16 <= $shared18)),
                      {
                        $require(($shared12 <= ($shared18 - $shared16))),
                        {
                          $require($read({{registryWord}},
                          4252186875,
                          {
                            {{clientsGroupId}},
                            $subjectArg(0)
                          })),
                          $write({{registryWord}},
                          1181875737,
                          {
                            $subjectPolicy,
                            {{meterId}},
                            86400,
                            $shared12,
                            {{dailyMintLimit}},
                            {{vaultWord}},
                            {{coinWord}},
                            0,
                            0
                          })
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
