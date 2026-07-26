# Release and Rollback

Application, database, policy and model releases are independent. Database changes are expand/migrate/contract. Policy activation supports percentage/tenant scope and immediate rollback. Model rollout uses compatibility cohort, signed manifest and kill switch. Mobile protocols support N-1 app version for the declared compatibility window. Rollback is tested in staging before promotion.
