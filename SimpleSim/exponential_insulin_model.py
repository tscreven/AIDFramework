import math
# From Loop, converted using ChatGPT
class ExponentialInsulinModel:
    def __init__(self, action_duration, peak_activity_time, delay=600):
        self.action_duration = action_duration
        self.peak_activity_time = peak_activity_time
        self.delay = delay
        
        self.τ = peak_activity_time * (1 - peak_activity_time / action_duration) / (1 - 2 * peak_activity_time / action_duration)
        self.a = 2 * self.τ / action_duration
        self.S = 1 / (1 - self.a + (1 + self.a) * math.exp(-action_duration / self.τ))

    @staticmethod
    def humalog():
        return ExponentialInsulinModel(360 * 60, 75 * 60, 10 * 60)
    
    @staticmethod
    def lyumjev():
        # Trying to set this to the same as Trio
        #return ExponentialInsulinModel(360 * 60, 55 * 60, 10 * 60)
        return ExponentialInsulinModel(600 * 60, 45 * 60, 0)

    @property
    def effect_duration(self):
        return self.action_duration + self.delay

    def percent_effect_remaining(self, time):
        time_after_delay = time - self.delay
        if time_after_delay <= 0:
            return 1
        elif time_after_delay >= self.action_duration:
            return 0
        else:
            t = time_after_delay
            return 1 - self.S * (1 - self.a) * ((pow(t, 2) / (self.τ * self.action_duration * (1 - self.a)) - t / self.τ - 1) * math.exp(-t / self.τ) + 1)
