from datetime import datetime
def assert_current(supplied:int,current:int,lease_expiry:datetime,now:datetime)->None:
    if supplied!=current: raise ValueError("ASSIGNMENT_STALE_FENCE")
    if now>=lease_expiry: raise ValueError("LEASE_EXPIRED")
