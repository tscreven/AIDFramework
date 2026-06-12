try:
    from gym.envs.registration import register
except ImportError:
    register = None

if register is not None:
    register(
        id='simglucose-v0',
        entry_point='simglucose.envs:T1DSimEnv',
    )
