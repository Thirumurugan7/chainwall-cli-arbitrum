{
  $require(($subjectPolicy == {{governancePolicyId}})),
  {
    $require(($subjectVault == {{vaultWord}})),
    {
      $require(($address({{coinKey}}) == {{coinWord}})),
      {
        $require(($subjectNativeValue == 0)),
        {
          $require(IF(($subjectId == {{unfreezeId}}),
          true,
          ($subjectId == {{wipeId}}))),
          {
            $require(($subjectArgCount == IF(($subjectId == {{wipeId}}),
            3,
            2))),
            {
              let $shared22 = IF(($subjectId == {{wipeId}}),
              $subjectArg(2),
              $subjectArg(1)),
              {
                $require(($shared22 > 0)),
                {
                  let $shared24 = $subjectPolicy,
                  {
                    let $shared34 = $keccak($subjectId,
                    {{coinWord}},
                    $subjectVault,
                    $subjectArg(0),
                    IF(($subjectId == {{wipeId}}),
                    $subjectArg(1),
                    0),
                    $read({{coinKey}},
                    141450134,
                    {
                      $subjectArg(0)
                    }),
                    $shared22),
                    {
                      let $shared35 = $read({{registryWord}},
                      83875018,
                      {
                        $shared24,
                        {{authNamespace}},
                        {{vaultWord}},
                        $shared34
                      }),
                      {
                        $require(IF(($shared35 > 0),
                        ($time <= $shared35),
                        false)),
                        {
                          $require(($shared35 <= ($time + 604800))),
                          $write({{registryWord}},
                          569500875,
                          {
                            $subjectPolicy,
                            {{authNamespace}},
                            {{vaultWord}},
                            $shared34,
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
