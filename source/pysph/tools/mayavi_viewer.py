"""A particle viewer using Mayavi.

This code uses the :py:class:`MultiprocessingClient` solver interface to
communicate with a running solver and displays the particles using
Mayavi.
"""

import sys
import math
import numpy
import socket

from enthought.traits.api import (HasTraits, Instance, on_trait_change,
        List, Str, Int, Range, Float, Bool, Password, Property)
from enthought.traits.ui.api import (View, Item, Group, HSplit, 
        ListEditor, EnumEditor, TitleEditor)
from enthought.mayavi.core.api import PipelineBase
from enthought.mayavi.core.ui.api import (MayaviScene, SceneEditor, 
                MlabSceneModel)
from enthought.pyface.timer.api import Timer
from enthought.tvtk.api import tvtk
from enthought.tvtk.array_handler import array2vtk

from pysph.base.api import ParticleArray
from pysph.solver.solver_interfaces import MultiprocessingClient

import logging
logger = logging.getLogger()

def set_arrays(dataset, particle_array):
    """ Code to add all the arrays to a dataset given a particle array."""
    props = set(particle_array.properties.keys())
    # Add the vector data.
    vec = numpy.empty((len(particle_array.x), 3), dtype=float)
    vec[:,0] = particle_array.u
    vec[:,1] = particle_array.v
    vec[:,2] = particle_array.w
    va = tvtk.to_tvtk(array2vtk(vec))
    va.name = 'velocity'
    dataset.data.point_data.add_array(vec)
    # Now add the scalar data.
    scalars = props - set(('u', 'v', 'w'))
    for sc in scalars:
        arr = particle_array.get(sc)
        va = tvtk.to_tvtk(array2vtk(arr))
        va.name = sc
        dataset.data.point_data.add_array(va)
    dataset._update_data()


##############################################################################
# `ParticleArrayHelper` class.
############################################################################## 
class ParticleArrayHelper(HasTraits):
    """
    This class manages a particle array and sets up the necessary
    plotting related information for it.
    """

    # The particle array we manage.
    particle_array = Instance(ParticleArray)

    # The name of the particle array.
    name = Str

    # The active scalar to view.
    scalar = Str('rho', desc='name of the active scalar to view') 

    # The mlab plot for this particle array.
    plot = Instance(PipelineBase)

    # List of available scalars in the particle array.
    scalar_list = List(Str)

    scene = Instance(MlabSceneModel)

    # Sync'd trait with the scalar lut manager.
    show_legend = Bool(False, desc='if the scalar legend is to be displayed')

    # Sync'd trait with the dataset to turn on/off visibility.
    visible = Bool(True, desc='if the particle array is to be displayed')

    ########################################
    # View related code.
    view = View(Item(name='name', 
                           show_label=False,
                           editor=TitleEditor()),
                Group(
                      Item(name='visible'),
                      Item(name='scalar',
                           editor=EnumEditor(name='scalar_list')
                          ),
                      Item(name='show_legend'),
                      ),
                )

    ######################################################################
    # Private interface.
    ######################################################################
    def _particle_array_changed(self, pa):
        self.name = pa.name
        # Setup the scalars.
        self.scalar_list = sorted(pa.properties.keys())

        # Update the plot.
        x, y, z, u, v, w = pa.x, pa.y, pa.z, pa.u, pa.v, pa.w
        s = getattr(pa, self.scalar)
        p = self.plot
        mlab = self.scene.mlab
        if p is None:
            src = mlab.pipeline.vector_scatter(x, y, z, u, v, w,
                                               scalars=s)
            p = mlab.pipeline.glyph(src, mode='point', scale_mode='none')
            p.actor.property.point_size = 3
            p.mlab_source.dataset.point_data.scalars.name = self.scalar
            scm = p.module_manager.scalar_lut_manager
            scm.set(show_legend=self.show_legend,
                    use_default_name=False,
                    data_name=self.scalar)
            self.sync_trait('visible', p.mlab_source.m_data,
                             mutual=True)
            self.sync_trait('show_legend', scm, mutual=True)
            #set_arrays(p.mlab_source.m_data, pa)
            self.plot = p
        else:
            if len(x) == len(p.mlab_source.x):
                p.mlab_source.set(x=x, y=y, z=z, scalars=s, u=u, v=v, w=w)
            else:
                p.mlab_source.reset(x=x, y=y, z=z, scalars=s, u=u, v=v, w=w)

    def _scalar_changed(self, value):
        p = self.plot
        if p is not None:
            p.mlab_source.scalars = getattr(self.particle_array, value)
            p.module_manager.scalar_lut_manager.data_name = value


##############################################################################
# `MayaviViewer` class.
############################################################################## 
class MayaviViewer(HasTraits):
    """
    This class represents a Mayavi based viewer for the particles.  They
    are queried from a running solver.
    """

    particle_arrays = List(Instance(ParticleArrayHelper), [])
    pa_names = List(Str, [])

    client = Instance(MultiprocessingClient)
    
    host = Str('localhost', desc='machine to connect to')
    port = Int(8800, desc='port to use to connect to solver')
    authkey = Password('pysph', desc='authorization key')
    host_changed = Bool(True)

    scene = Instance(MlabSceneModel, ())

    controller = Property()

    ########################################
    # Timer traits.
    timer = Instance(Timer)
    interval = Range(2, 20.0, 5.0, 
                     desc='frequency in seconds with which plot is updated')
    
    ########################################
    # Solver info/control.
    current_time = Float(0.0, desc='the current time in the simulation')
    iteration = Int(0, desc='the current iteration number')
    pause_solver = Bool(False, desc='if the solver should be paused')

    ########################################
    # The layout of the dialog created
    view = View(HSplit(
                  Group(
                    Group(
                          Item(name='host'),
                          Item(name='port'),
                          Item(name='authkey'),
                          label='Connection',
                          ),
                    Group(
                          Item(name='current_time'),
                          Item(name='iteration'),
                          Item(name='pause_solver'),
                          Item(name='interval'),
                          label='Solver',
                          ),
                    Group(
                          Item(name='particle_arrays',
                               style='custom',
                               show_label=False,
                               editor=ListEditor(use_notebook=True,
                                                 deletable=False,
                                                 page_name='.name'
                                                 )
                               )
                         ),
                  ),
                  Item('scene', editor=SceneEditor(scene_class=MayaviScene),
                         height=480, width=500, show_label=False),
                      ),
                resizable=True,
                title='Mayavi Particle Viewer'
                )

    ######################################################################
    # `MayaviViewer` interface.
    ######################################################################
    @on_trait_change('scene.activated')
    def start_timer(self):
        # Just accessing the timer will start it.
        t = self.timer
        if not t.IsRunning():
            t.Start(int(self.interval*1000))

    @on_trait_change('scene.activated')
    def update_plot(self):
        # do not update if solver is paused
        if self.pause_solver:
            return
        controller = self.controller
        if controller is None:
            return
        
        self.current_time = controller.get_t()
        for idx, name in enumerate(self.pa_names):
            pa = controller.get_named_particle_array(name)
            self.particle_arrays[idx].particle_array = pa

    ######################################################################
    # Private interface.
    ######################################################################
    @on_trait_change('host,port,authkey')
    def _mark_reconnect(self):
        self.host_changed = True

    def _get_controller(self):
        ''' get the controller, also sets the iteration count '''
        reconnect = self.host_changed
        
        if not reconnect:
            try:
                c = self.client.controller
                self.iteration = c.get_count()
            except Exception as e:
                logger.info('Error: no connection or connection closed: reconnecting')
                reconnect = True
                self.client = None
        
        if reconnect:
            self.host_changed = False
            try:
                if MultiprocessingClient.is_available((self.host, self.port)):
                    self.client = MultiprocessingClient(address=(self.host, self.port),
                                                        authkey=self.authkey)
                else:
                    return None
            except Exception as e:
                logger.info('Could not connect: check if solver is running')
                return None
            c = self.client.controller
            self.iteration = c.get_count()
        
        return self.client.controller
    
    def _client_changed(self, old, new):
        if self.client is None:
            return
        else:
            self.pa_names = self.client.controller.get_particle_array_names()

        self.scene.mayavi_scene.children[:] = []
        self.particle_arrays = [ParticleArrayHelper(scene=self.scene, name=x) for x in
                                self.pa_names]
        # Turn on the legend for the first particle array.
        if len(self.particle_arrays) > 0:
            self.particle_arrays[0].show_legend = True

    def _timer_event(self):
        # catch all Exceptions else timer will stop
        try:
            self.update_plot()
        except Exception as e:
            logger.info('Exception: %s caught in timer_event'%e)

    def _interval_changed(self, value):
        t = self.timer
        if t is None:
            return
        if t.IsRunning():
            t.Stop()
            t.Start(int(value*1000))

    def _timer_default(self):
        return Timer(int(self.interval*1000), self._timer_event)

    def _pause_solver_changed(self, value):
        c = self.client.controller
        if value:
            c.pause_on_next()
        else:
            c.cont()

######################################################################
def usage():
    print """Usage:
mayavi_viewer.py <trait1=value> <trait2=value> ...

Where the options <trait1=value> are optional.

Example::

  $ mayavi_viewer.py interval=10 host=localhost port=8900
"""

def error(msg):
    print msg
    sys.exit()

def main(args=None):
    if args is None:
        args = sys.argv[1:]

    if '-h' in args or '--help' in args:
        usage()
        sys.exit(0)

    kw = {}
    for arg in args:
        if '=' not in arg:
            usage()
            sys.exit(1)
        key, arg = [x.strip() for x in arg.split('=')]
        kw[key] = eval(arg, math.__dict__)


    m = MayaviViewer(**kw)
    m.configure_traits()

if __name__ == '__main__':
    main()

