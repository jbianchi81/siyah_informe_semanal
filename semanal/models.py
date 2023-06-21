from django.db import models
from django.contrib.gis.db.models import GeometryField as PostgisGeometryField
from djgeojson.fields import GeometryField
from psqlextra.models import PostgresModel
from datetime import date
from django.contrib import admin
from collections import OrderedDict

class Region(PostgresModel):
    id = models.CharField(max_length=200,primary_key=True)
    nombre = models.CharField(max_length=200,unique=True)
    geom = GeometryField()
    def __str__(self):
        return "%s [%s]" % (self.nombre, self.id)
# CREATE TABLE informe_semanal.regiones (id varchar not null primary key,nombre varchar not null,geom geometry not null);

class Tramo(PostgresModel):
    id = models.CharField(max_length=200,primary_key=True)
    region = models.ForeignKey(Region, on_delete=models.CASCADE)
    nombre = models.CharField(max_length=200,unique=True)
    geom = GeometryField()
    def __str__(self):
        return "%s [%s]" % (self.nombre, self.id)
# CREATE TABLE informe_semanal.tramos (id varchar not null primary key, region_id  varchar not null references informe_semanal.regiones(id), nombre varchar not null, geom geometry not null);

class Informe(PostgresModel):
    fecha = models.DateField(primary_key=True)
    texto_general = models.CharField(max_length=20000)
    revisado = models.BooleanField(default=False)
    def __str__(self):
        return "%s" % (self.fecha.isoformat())
    def isLast(self):
        last_informe = Informe.objects.filter(revisado=True).order_by("-fecha")[0]
        return last_informe.fecha == (date.fromisoformat(self.fecha) if isinstance(self.fecha,str) else self.fecha)
    @admin.display(
        boolean=False,
        ordering='fecha',
        description='fecha',
    )
    def fechaIsoFormat(self):
        return self.fecha.isoformat()
    @admin.display(
        boolean=False,
        description='contenido region',
    )
    def contenidoLength(self):
        return len(self.contenido_set.all())
    @admin.display(
        boolean=False,
        description='contenido tramo',
    )
    def contenidoTramoLength(self):
        return len(self.contenidotramo_set.all())
    @admin.display(
        boolean=False,
        description='dato',
    )
    def datoLength(self):
        return len(self.dato_set.all())
    def to_dict(self):
        informe_dict = {
            "fecha": self.fecha.isoformat(),
            "texto_general": self.texto_general,
            "revisado": self.revisado,
            "contenido": {}
        }
        for contenido in self.contenido_set.all():
            informe_dict["contenido"][contenido.region.id] = contenido.to_dict()
        for contenidotramo in self.contenidotramo_set.all():
            if contenidotramo.tramo.region_id not in informe_dict["contenido"]:
                informe_dict["contenido"][contenidotramo.tramo.region_id] = {
                    "region_id": contenidotramo.tramo.region_id,
                    "texto": None
                }
            if "tramos" not in informe_dict["contenido"][contenidotramo.tramo.region_id]:
                informe_dict["contenido"][contenidotramo.tramo.region.id]["tramos"] = {}
            informe_dict["contenido"][contenidotramo.tramo.region.id]["tramos"][contenidotramo.tramo.id] = contenidotramo.to_dict()
        for dato in self.dato_set.all():
            if dato.seccion.region_id not in informe_dict["contenido"]:
                region = Region.objects.get(pk=dato.seccion.region_id)
                informe_dict["contenido"][dato.seccion.region_id] = {
                    "region_id": region.id, # dato.seccion.region_id,
                    "region": region.nombre,
                    "texto": None
                }
            if dato.seccion.tramo_id is not None:
                if "tramos" not in informe_dict["contenido"][dato.seccion.region_id]:
                    informe_dict["contenido"][dato.seccion.region_id]["tramos"] = {}
                if dato.seccion.tramo_id not in informe_dict["contenido"][dato.seccion.region_id]["tramos"]:
                    tramo = Tramo.objects.get(pk=dato.seccion.tramo_id)
                    informe_dict["contenido"][dato.seccion.region_id]["tramos"][dato.seccion.tramo_id] = {
                        "tramo_id": tramo.id, # dato.seccion.tramo_id,
                        "tramo": tramo.nombre,
                        "texto": None
                    }
                if "datos" not in informe_dict["contenido"][dato.seccion.region_id]["tramos"][dato.seccion.tramo_id]:
                    informe_dict["contenido"][dato.seccion.region_id]["tramos"][dato.seccion.tramo_id]["datos"] = []
                informe_dict["contenido"][dato.seccion.region_id]["tramos"][dato.seccion.tramo_id]["datos"].append(dato.to_dict())
            else:
                if "datos" not in informe_dict["contenido"][dato.seccion.region_id]:
                    informe_dict["contenido"][dato.seccion.region_id]["datos"] = []
                informe_dict["contenido"][dato.seccion.region_id]["datos"].append(dato.to_dict())
        informe_dict_contenido = []
        for region_id in informe_dict["contenido"]:
            contenido_region = informe_dict["contenido"][region_id]
            if "tramos" in contenido_region:
                contenido_tramos = []
                for tramo_id in contenido_region["tramos"]:
                    contenido_tramos.append(contenido_region["tramos"][tramo_id])
                contenido_region["tramos"] = contenido_tramos
            informe_dict_contenido.append(contenido_region)
        informe_dict["contenido"] = informe_dict_contenido
        return informe_dict
    def to_list(self):
        informe_list = [self.fecha, self.texto_general, self.revisado]
        return informe_list
    @staticmethod
    def get_header():
        return ["fecha","texto_general","revisado"]
    def to_bookdict(self, headers=True):
        bookdict = OrderedDict()
        if headers:
            bookdict["informe"] = [self.get_header(), self.to_list()]
            bookdict["contenido"] = [Contenido.get_header()]  + [contenido.to_list() for contenido in self.contenido_set.all()]
            bookdict["contenidotramo"] =  [ContenidoTramo.get_header()] + [contenidotramo.to_list() for contenidotramo in self.contenidotramo_set.all()]
            bookdict["dato"] = [Dato.get_header()] + [dato.to_list() for dato in self.dato_set.all()]
            return bookdict
        bookdict["informe"] = [self.to_list()]
        bookdict["contenido"] = [contenido.to_list() for contenido in self.contenido_set.all()]
        bookdict["contenidotramo"] = [contenidotramo.to_list() for contenidotramo in self.contenidotramo_set.all()]
        bookdict["dato"] = [dato.to_list() for dato in self.dato_set.all()]
        return bookdict

    class Meta:
        ordering = ('-fecha',)

# CREATE TABLE informe_semanal.informe (fecha date not null primary key, texto_general varchar);

class Contenido(PostgresModel):
    id = models.BigAutoField(primary_key=True)
    fecha = models.ForeignKey(Informe, on_delete=models.CASCADE,verbose_name="fecha informe")
    fecha_actualizado = models.DateField(blank=True,null=True,verbose_name="fecha actualizado")
    region = models.ForeignKey(Region, on_delete=models.CASCADE)
    texto = models.CharField(max_length=20000)
    # def __init__(self):
    #     super(Contenido,self).__init__(self)
    def __str__(self):
        return "%s (%s)[%s]" % (self.region.id, str(self.fecha), str(self.fecha_actualizado))
    # def save(self, *args, **kwargs):
    #     if self.fecha_actualizado is None:
    #         self.fecha_actualizado = self.fecha
    #     super(Contenido, self).save(*args, **kwargs)
    def to_dict(self):
        return {
            "region_id": self.region.id,
            "region": self.region.nombre,
            "texto": self.texto, 
            "fecha_actualizado": self.fecha_actualizado
        }
    def to_list(self,header=False):
        contenido_list =  [self.region.id, self.texto, self.fecha_actualizado]
        return contenido_list
    @staticmethod
    def get_header():
        return ["region","texto","fecha_actualizado"]
    class Meta:
        unique_together = ('fecha','region')
        ordering = ("fecha","region")
# CREATE TABLE informe_semanal.contenido (id serial primary key, fecha date references informe_semanal.informe(fecha) ON DELETE CASCADE NOT NULL, region_id varchar references informe_semanal.regiones(id) ON DELETE CASCADE NOT NULL, texto varchar not null, unique (fecha, region_id));

class ContenidoTramo(PostgresModel):
    id = models.BigAutoField(primary_key=True)
    fecha = models.ForeignKey(Informe, on_delete=models.CASCADE, verbose_name="fecha informe")
    fecha_actualizado = models.DateField(blank=True,null=True, verbose_name="fecha actualizado")
    tramo = models.ForeignKey(Tramo, on_delete=models.CASCADE)
    texto = models.CharField(max_length=20000)
    def __str__(self):
        return "%s (%s)[%s]" % (self.tramo.id, str(self.fecha), str(self.fecha_actualizado))
    # def save(self, *args, **kwargs):
    #     if self.fecha_actualizado is None:
    #         self.fecha_actualizado = self.fecha
    #     super(ContenidoTramo, self).save(*args, **kwargs)
    def to_dict(self):
        return {
            "tramo_id": self.tramo_id,
            "tramo": self.tramo.nombre,
            "texto": self.texto,
            "fecha_actualizado": self.fecha_actualizado
        }
    def to_list(self):
        contenidotramo_list = [self.tramo.id, self.texto, self.fecha_actualizado]
        return contenidotramo_list
    @staticmethod
    def get_header():
        return ["tramo","texto","fecha_actualizado"]
    class Meta:
        unique_together = ('fecha','tramo')
        ordering = ('fecha','tramo')
# CREATE TABLE informe_semanal.contenido_tramo (id serial primary key, fecha date references informe_semanal.informe(fecha) ON DELETE CASCADE NOT NULL, tramo_id varchar references informe_semanal.tramos(id) ON DELETE CASCADE NOT NULL, texto varchar not null, unique (fecha, tramo_id));

class Estacion(PostgresModel):
    unid = models.IntegerField(primary_key=True)
    nombre = models.CharField(max_length=255)
    geom = PostgisGeometryField()
    class Meta:
        managed = False
        db_table = "estaciones"
    def __str__(self):
        return "%s [%i]" % (self.nombre, self.unid)
        

class Seccion(PostgresModel):
    id = models.CharField(max_length=200,primary_key=True)
    nombre = models.CharField(max_length=200,unique=True)
    estacion = models.ForeignKey(Estacion, db_column="unid",on_delete=models.CASCADE)
    region = models.ForeignKey(Region,on_delete=models.DO_NOTHING)
    tramo = models.ForeignKey(Tramo,blank=True,null=True,on_delete=models.DO_NOTHING)
    def __str__(self):
        return "%s [%s](%i)" % (self.nombre, self.id, self.estacion.unid)
    class Meta:
        ordering = ('id',)
# CREATE TABLE informe_semanal.secciones (nombre varchar not null, id varchar not null primary key, estacion_id int not null references public.estaciones(unid), region_id varchar not null references informe_semanal.regiones(id), tramo_id varchar references informe_semanal.tramos(id));

class Var(PostgresModel):
    id = models.IntegerField(primary_key=True)
    nombre = models.CharField(max_length=255)
    class Meta:
        managed = False
        db_table = "var"
    def __str__(self):
        return "%s [%i]" % (self.nombre, self.id)

class Variable(PostgresModel):
    id = models.CharField(max_length=200,primary_key=True)
    nombre = models.CharField(max_length=200,unique=True)
    units = models.CharField(max_length=200)
    var = models.ForeignKey(Var, on_delete=models.CASCADE)
    def __str__(self):
        return "%s [%s]" % (self.nombre, self.id)
# CREATE TABLE informe_semanal.variables (nombre varchar not null, id varchar not null primary key, units varchar not null, var_id int not null references public.var(id));

class Tendencia(PostgresModel):
    id = models.CharField(max_length=200,primary_key=True)
    nombre = models.CharField(max_length=200,unique=True)
    def __str__(self):
        return "%s [%s]" % (self.nombre,self.id)
    class Meta:
        ordering = ('id',)
# CREATE TABLE informe_semanal.tendencia (id varchar not null primary key, nombre varchar not null);

class Dato(PostgresModel):
    id = models.BigAutoField(primary_key=True)
    fecha = models.ForeignKey(Informe, on_delete=models.CASCADE)
    fecha_actualizado = models.DateField(blank=True,null=True)
    seccion = models.ForeignKey(Seccion, on_delete=models.CASCADE)
    variable = models.ForeignKey(Variable, on_delete=models.CASCADE)
    min_obs = models.FloatField(null=True,blank=True)
    mean_obs = models.FloatField(null=True,blank=True)
    max_obs = models.FloatField(null=True,blank=True)
    min_prono = models.FloatField(null=True,blank=True)
    mean_prono = models.FloatField(null=True,blank=True)
    max_prono = models.FloatField(null=True,blank=True)
    tendencia = models.ForeignKey(Tendencia,on_delete=models.DO_NOTHING,null=True,blank=True)
    def __str__(self):
        return "%s [%s] (%s)" % (self.seccion.id, self.variable.id, str(self.fecha))
    # def save(self, *args, **kwargs):
    #     if self.fecha_actualizado is None:
    #         self.fecha_actualizado = self.fecha.fecha
    #     super(Dato, self).save(*args, **kwargs)
    def to_dict(self):
        return {
            "seccion": self.seccion.nombre,
            "seccion_id": self.seccion.id,
            "estacion_id": self.seccion.estacion.unid,
            "tramo_id": self.seccion.tramo_id,
            "variable": self.variable.nombre,
            "variable_id": self.variable.id,
            "units": self.variable.units, 
            "min_obs": self.min_obs,
            "mean_obs": self.mean_obs,
            "max_obs": self.max_obs,
            "min_prono": self.min_prono,
            "mean_prono": self.mean_prono,
            "max_prono": self.max_prono,
            "tendencia": self.tendencia.nombre if self.tendencia is not None else None,
            "tendencia_id": self.tendencia.id if self.tendencia is not None else None,
            "fecha_actualizado": self.fecha_actualizado.isoformat() if self.fecha_actualizado is not None else None
        }
    def to_list(self):
        dato_list = [self.seccion.id, self.variable.id, self.min_obs, self.mean_obs, self.max_obs, self.min_prono, self.mean_prono, self.max_prono,self.tendencia.id if self.tendencia is not None else None, self.fecha_actualizado]
        return dato_list
    @staticmethod
    def get_header():
        return ["seccion", "variable", "min_obs", "mean_obs", "max_obs", "min_prono", "mean_prono", "max_prono","tendencia", "fecha_actualizado"]

    class Meta:
        unique_together = ('fecha','seccion')
#CREATE TABLE informe_semanal.datos (id serial primary key, fecha date references informe_semanal.informe(fecha) ON DELETE CASCADE NOT NULL, seccion varchar references informe_semanal.secciones(id) on delete cascade not null, variable varchar references informe_semanal.variables(id) on delete cascade not null, min_obs float, max_obs float, promedio_obs float, min_prono float, max_prono float, promedio_prono float, tendencia varchar references informe_semanal.tendencia(id) on delete cascade, unique (fecha,seccion));

class MapaBase(PostgresModel):
    orden = models.IntegerField(primary_key=True)
    titulo = models.CharField(max_length=1000)
    descripcion = models.CharField(max_length=20000)
    href = models.URLField()

    def __str__(self):
        return "%s [%s] (%s): %s" % (str(self.orden), self.titulo, str(self.href), self.descripcion)
    # def save(self, *args, **kwargs):
    #     if self.fecha_actualizado is None:
    #         self.fecha_actualizado = self.fecha.fecha
    #     super(Dato, self).save(*args, **kwargs)
    def to_dict(self):
        return {
            "orden": self.orden,
            "titulo": self.titulo,
            "descripcion": self.descripcion,
            "href": self.href
        }
    def to_list(self):
        return [self.orden, self.titulo, self.descripcion, self.href]
    @staticmethod
    def get_header():
        return ["orden", "titulo", "descripcion", "href"]