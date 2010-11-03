""" Classes to get the various functions """
import funcs.basic_funcs as basic
import funcs.boundary_funcs as boundary
import funcs.density_funcs as density
import funcs.energy_funcs as energy
import funcs.eos_funcs as eos
import funcs.external_force as external
import funcs.position_funcs as position
import funcs.pressure_funcs as pressure
import funcs.viscosity_funcs as viscosity
import funcs.xsph_funcs as xsph

#base class
class Function(object):
    def __init__(self):
        pass

    def get_func(self, source, dst):
        raise NotImplementedError

#basic functions
class SPHInterpolation(Function):
    
    def __init__(self, prop_name=""):
        self.prop_name = prop_name
    
    def get_func(self, source, dest):
        return basic.SPH(source=source, dest=dest, prop_name=self.prop_name)
        
class SimpleDerivative(Function):
    
    def __init__(self, prop_name=""):
        self.prop_name = prop_name

    def get_func(self, source, dest):
        return basic.SPHSimpleDerivative(source=source, dest=dest, 
                                   prop_name=self.prop_name)
class Gradient(Function):
    
    def __init__(self, prop_name=""):
        self.prop_name = prop_name

    def get_func(self, source, dest):
        return basic.SPHGrad(source=source, dest=dest, prop_name=self.prop_name)

class Laplacian(Function):
    
    def __init__(self, prop_name=""):
        self.prop_name = prop_name

    def get_func(self, source, dest):
        return basic.SPHLaplacian(source, dest=dest, prop_name=self.prop_name)

class NeighborCount(Function):
    
    def get_func(self, source, dest):
        return basic.CountNeighbors(source=source, dest=dest)

#boundary functions

class MonaghanBoundaryForce(Function):
    
    def __init__(self, delp = 1.0):
        self.delp = delp
        
    def get_func(self, source, dest):
        func = boundary.MonaghanBoundaryForce(source=source, dest=dest,
                                              delp = self.delp)
        func.tag = 'velocity'
        return func

class BeckerBoundaryForce(Function):
    
    def __init__(self, sound_speed):
        self.sound_speed = sound_speed

    def get_func(source, dest):
        func = boundary.BeckerBoundaryForce(source=source, dest=dest,
                                            sound_speed=self.sound_speed)
        func.tag = 'velocity'
        return func

class LennardJonesForce(Function):
    
    def __init__(self, D, ro, p1, p2):
        self.D = D
        self.ro = ro
        self.p1 = p1
        self.p2 = p2

    def get_func(self, source, dest):
        func = boundary.LennardJonesForce(source=source, dest=dest,
                                          D=self.D, ro=self.ro, 
                                          p1=self.p1, p2=self.p2)
        func.tag = "velocity"
        return func

#density funcs

class SPHRho(Function):
    def get_func(self, source, dest):
        func =  density.SPHRho(source=source, dest=dest)
        func.tag = 'density'
        return func

class SPHDensityRate(Function):
    def get_func(self, source, dest):
        func =  density.SPHDensityRate(source=source, dest=dest)
        func.tag = "density"
        return func

#energy equation

class EnergyEquationNoVisc(Function):
    
    def get_func(self, source, dest):
        func = energy.EnergyEquation(source=source, dest=dest)
        func.tag = "energy"
        return func

class EnergyEquationAVisc(Function):
    
    def __init__(self, beta=1.0, alpha=1.0, gamma=1.4, eta=0.1):
        self.beta = beta
        self.alpha = alpha
        self.gamma = gamma
        self.eta = eta

    def get_func(self, source, dest):
        func =  energy.EnergyEquationAVisc(source=source, dest=dest, 
                                           beta=self.beta,
                                           gamma=self.gamma, alpha=self.alpha, 
                                           eta=self.eta)
        func.tag = 'energy'
        return func


class EnergyEquation(Function):
    
    def __init__(self, beta=1.0, alpha=1.0, gamma=1.4, eta=0.1):
        self.beta = beta
        self.alpha = alpha
        self.gamma = gamma
        self.eta = eta        
        
    def get_func(self, source, dest):
        func =  energy.EnergyEquation(source=source, dest=dest, beta=self.beta,
                                      gamma=self.gamma, alpha=self.alpha, 
                                      eta=self.eta)
        func.tag = "energy"
        return func


#state equation

class IdealGasEquation(Function):
    def __init__(self, gamma=1.4):
        self.gamma = gamma

    def get_func(self, source, dest):
        func =  eos.IdealGasEquation(source=source, dest=dest, gamma=self.gamma)
        func.tag = "state"
        return func

class TaitEquation(Function):
    def __init__(self, co, ro, gamma=7.0):
        self.co = co
        self.ro = ro
        self.gamma = gamma

    def get_func(self, source, dest):
        func =  eos.TaitEquation(source=source, dest=dest, co=self.co, 
                                 ro=self.ro, gamma=self.gamma)
        func.tag = "state"
        return func

#external forces

class GravityForce(Function):
    def __init__(self, gx=0.0, gy=-9.81, gz=0.0):
        self.gx=gx
        self.gy=gy
        self.gz=gz

    def get_func(self, source, dest):
        func =  external.GravityForce(source=source, dest=dest, gx=self.gx,
                                      gy=self.gy, gz=self.gz)
        func.tag = "velocity"
        return func

class VectorForce(Function):
    def __init__(self, force):
        self.force = force

    def get_func(self, source, dest):
        return external.VectorForce(source=source, dest=dest, force=force)

class MoveCircleX(Function):
    def get_func(self, source, dest):
        func =  external.MoveCircleX(source=source, dest=dest)
        func.tag = "velocity"
        return func    

class MoveCircleY(Function):
    def get_func(self, source, dest):
        func =  external.MoveCircleY(source=source, dest=dest)
        func.tag = "velocity"
        return func

#position funcs

class PositionStepping(Function):
    def get_func(self, source, dest):
        func =  position.PositionStepping(source=source, dest=dest)
        func.tag = "position"
        return func

class SPHPressureGradient(Function):
    def get_func(self, source, dest):
        func =  pressure.SPHPressureGradient(source=source, dest=dest)    
        func.tag = "velocity"
        return func

class MomentumEquation(Function):
    def __init__(self, alpha=1.0, beta=1.0, gamma=1.4, eta=0.1):
        self.alpha=alpha
        self.beta=beta
        self.gamma=gamma
        self.eta=eta

    def get_func(self, source, dest):
        func =  pressure.MomentumEquation(source=source, dest=dest,
                                          alpha=self.alpha,
                                          beta=self.beta, gamma=self.gamma, 
                                          eta=self.eta, 
                                          )
        func.tag = "velocity"
        return func

#viscosity equations

class MonaghanArtificialVsicosity(Function):
    def __init__(self, alpha=1.0, beta=1.0, gamma=1.4, eta=0.1):
        self.alpha=alpha
        self.beta=beta
        self.gamma=gamma
        self.eta=eta

    def get_func(self, source, dest):
        func=viscosity.MonaghanArtificialVsicosity(
            source=source, dest=dest, 
            alpha=self.alpha, beta=self.beta,
            gamma=self.gamma, eta=self.eta)
        func.tag = "velocity"
        return func

class MorrisViscosity(Function):
    def __init__(self, mu='mu'):
        self.mu=mu
        
    def get_func(self, source, dest):
        func = viscosity.MorrisViscosity(source=source, dest=dest,
                                         mu=self.mu)
        func.tag = "velocity"
        return func

#xsph funcs

class XSPHCorrection(Function):
    def __init__(self, eps=0.5):
        self.eps = eps
        
    def get_func(self, source, dest):
        func =  xsph.XSPHCorrection(source=source, dest=dest, eps=self.eps)
        func.tag = "velocity"
        return func

class XSPHDensityRate(Function):
    
    def get_func(self, source, dest):
        func = xsph.XSPHDensityRate(source=source, dest=dest)
        func.tag = "density"
        return func
