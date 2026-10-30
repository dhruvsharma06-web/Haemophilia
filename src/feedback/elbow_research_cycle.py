"""Causal local-extrema cycle prototype with no absolute ready-angle gate.

Relative detection tolerances are not medical range prescriptions. Binary form
classification and user confirmation remain separate from geometric detection.
"""
from collections import deque
from dataclasses import dataclass
import numpy as np

@dataclass(frozen=True)
class CycleConfig:
    angle_channel:int=0
    onset_delta:float=10.
    reversal_delta:float=6.
    minimum_excursion:float=15.
    minimum_duration:float=.8
    return_fraction:float=.8
    plateau_hold:float=.2
    onset_hold:float=.10
    reversal_hold:float=.10
    maximum_gap:float=.30
    maximum_duration:float=10.
    pre_roll:float=.15
    rearm_delay:float=.20
    median_seconds:float=.13

class AlternatingCycleController:
    def __init__(self,starting_hand='Left',alternate=True,config=None):
        if starting_hand not in ('Left','Right'):raise ValueError('Invalid side')
        self.hand=starting_hand;self.alternate=alternate;self.config=config or CycleConfig()
        self.last_t=None;self.pending=None;self.attempts=0;self.correct_reps=0
        self.buffer=deque();self.last_end=-np.inf;self.rearm_at=-np.inf
        self.reset_tracking()

    def reset_tracking(self):
        self.state='READY';self.high=None;self.high_t=None;self.low=None
        self.return_peak=None;self.return_peak_t=None;self.start=None
        self.condition_since=None;self.last_seen=None;self.angle=None;self.angle_history=deque()

    def _hold(self,condition,t,duration):
        if not condition:self.condition_since=None;return False
        if self.condition_since is None:self.condition_since=t
        return t-self.condition_since+1e-9>=duration

    def confirm_rep(self,accepted):
        if self.pending is None:raise ValueError('No cycle to confirm')
        self.attempts+=1
        if accepted:
            self.correct_reps+=1
            if self.alternate:self.hand='Right' if self.hand=='Left' else 'Left'
        self.last_end=self.pending['end_sec'];self.rearm_at=self.last_end+self.config.rearm_delay
        self.pending=None;self.reset_tracking()
        # Prime the next side only from observations already received.
        recent=[(t,float(r[self.hand][self.config.angle_channel])) for t,r in self.buffer if t>=self.last_t-.35]
        recent=[p for p in recent if np.isfinite(p[1])]
        if recent:
            self.high_t,self.high=max(recent,key=lambda p:p[1])

    def _emit(self,t,end,kind):
        samples=[(s,r[self.hand]) for s,r in self.buffer if self.start<=s<=end+1e-9]
        if len(samples)<8 or end-self.start<self.config.minimum_duration:return None
        excursion=self.high-self.low
        if excursion<self.config.minimum_excursion:return None
        event={'hand':self.hand,'start_sec':samples[0][0],'end_sec':samples[-1][0],
            'detected_at_sec':t,'boundary_delay_sec':t-samples[-1][0],
            'times':np.asarray([p[0] for p in samples]),'trace':np.asarray([p[1] for p in samples]),
            'excursion':excursion,'duration':samples[-1][0]-samples[0][0],
            'baseline':self.high,'minimum_angle':self.low,'closure_kind':kind,
            'relative_return':(self.return_peak-self.low)/max(excursion,1e-6)}
        self.pending=event;self.state='REVIEW';return event

    def update(self,t,measurements):
        t=float(t)
        if self.last_t is not None and t<=self.last_t:raise ValueError('Nonmonotonic timestamps')
        self.last_t=t
        self.buffer.append((t,{h:np.asarray(measurements[h],float).copy() for h in ('Left','Right')}))
        while self.buffer and t-self.buffer[0][0]>self.config.maximum_duration+1.:self.buffer.popleft()
        if self.pending is not None:return None,self.live_state()
        a=float(measurements[self.hand][self.config.angle_channel])
        if not np.isfinite(a):
            self.condition_since=None;self.angle_history.clear()
            if self.last_seen is not None and t-self.last_seen>self.config.maximum_gap:self.reset_tracking()
            return None,{**self.live_state(),'tracking':'UNASSESSED'}
        if self.last_seen is not None and t-self.last_seen>self.config.maximum_gap:self.reset_tracking()
        self.last_seen=t;self.angle_history.append((t,a))
        while self.angle_history and t-self.angle_history[0][0]>self.config.median_seconds:self.angle_history.popleft()
        self.angle=float(np.median([p[1] for p in self.angle_history]));a=self.angle
        if t<self.rearm_at:return None,self.live_state()
        if self.state=='READY':
            if self.high is None or a>self.high:
                self.high=a;self.high_t=t
            elif a>=self.high-1.5:
                # Prefer a recent near-maximum boundary over a long idle section.
                self.high_t=t
            if self._hold(a<=self.high-self.config.onset_delta,t,self.config.onset_hold):
                self.start=max(self.last_end,self.high_t-self.config.pre_roll)
                self.low=a;self.state='FLEXING';self.condition_since=None
            elif self.high_t is not None and t-self.high_t>2.5 and a>self.high-self.config.onset_delta:
                self.high=a;self.high_t=t
        elif self.state=='FLEXING':
            self.low=min(self.low,a)
            if self._hold(a>=self.low+self.config.reversal_delta,t,self.config.reversal_hold):
                self.return_peak=a;self.return_peak_t=t;self.state='RETURNING';self.condition_since=None
        elif self.state=='RETURNING':
            if a>self.return_peak:
                self.return_peak=a;self.return_peak_t=t
            elif a>=self.return_peak-1.5:
                self.return_peak_t=t if a>self.high else self.return_peak_t
            fraction=(self.return_peak-self.low)/max(self.high-self.low,1e-6)
            # A sustained new descent closes the previous visible cycle, even if
            # its return was incomplete; form assessment must see that attempt.
            turn=a<=self.return_peak-self.config.onset_delta and fraction>=.25
            if self._hold(turn,t,self.config.onset_hold):
                event=self._emit(t,self.return_peak_t,'next_descent')
                if event is not None:return event,self.live_state()
                self.reset_tracking()
            elif not turn and fraction>=self.config.return_fraction:
                tail=[p[1] for p in self.angle_history]
                plateau=(t-self.return_peak_t>=self.config.plateau_hold and max(tail)-min(tail)<=5.)
                near_rest=a>=self.high-3. and t-self.start>=self.config.minimum_duration
                if plateau or near_rest:
                    event=self._emit(t,t,'return_plateau' if plateau else 'near_rest')
                    if event is not None:return event,self.live_state()
        if self.start is not None and t-self.start>self.config.maximum_duration:
            self.reset_tracking();return None,{**self.live_state(),'tracking':'CYCLE_TIMEOUT'}
        return None,self.live_state()

    def live_state(self):
        return {'stage':self.state,'expected_hand':self.hand,'baseline':self.high,'angle':self.angle,
            'attempts':self.attempts,'correct_reps':self.correct_reps,'tracking':'OBSERVED',
            'detection_tolerances':self.config.__dict__}
