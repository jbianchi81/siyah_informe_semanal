from semanal.models import Region, Tramo, Seccion, Variable, Estacion, Var, Tendencia
import json
import pandas
from psqlextra.query import ConflictAction

def importRegionesFromGeoJson(filename="semanal/static/semanal/json/regiones_semanal.json"):
    f = open(filename)
    regiones_geojson = json.load(f)
    f.close()
    for feature in regiones_geojson["features"]:
        region = Region.objects.on_conflict(["id"],ConflictAction.UPDATE).on_conflict(["nombre"],ConflictAction.UPDATE).insert(id=feature["properties"]["id"],nombre=feature["properties"]["nombre"],geom=feature["geometry"])

def importTramosFromGeoJson(filename="semanal/static/semanal/json/tramos_semanal.json"):
    f = open(filename)
    tramos_geojson = json.load(f)
    f.close()
    for feature in tramos_geojson["features"]:
        try:
            region = Region.objects.get(id=feature["properties"]["region_id"])
        except Region.DoesNotExist as e:
            print("WARN: " + str(e))
            continue
        tramo = Tramo.objects.on_conflict(["id"],ConflictAction.UPDATE).on_conflict(["nombre"],ConflictAction.UPDATE).insert(id=feature["properties"]["id"],nombre=feature["properties"]["nombre"],geom=feature["geometry"],region=region)

def importVariablesFromCsv(filename="semanal/static/semanal/csv/variables.csv"):
    data = pandas.read_csv(filename,header=0)
    for i, row in data.iterrows():
        try:
            var = Var(id=row["var_id"])
        except Var.DoesNotExist as e:
            print("WARN: " + str(e))
            continue
        Variable.objects.on_conflict(["id"],ConflictAction.UPDATE).on_conflict(["nombre"],ConflictAction.UPDATE).insert(id=row["id"],nombre=row["nombre"],units=row["units"],var=var)

def importSeccionesFromCsv(filename="semanal/static/semanal/csv/secciones.csv"):
    data = pandas.read_csv(filename,header=0)
    for i, row in data.iterrows():
        try:
            estacion = Estacion(unid=row["estacion_id"])
        except Estacion.DoesNotExist as e:
            print("WARN: " + str(e))
            continue
        try:
            region = Region(id=row["region_id"])
        except Region.DoesNotExist as e:
            print("WARN: " + str(e))
            continue
        if pandas.notna(row["tramo_id"]):
            try:
                tramo = Tramo(id=row["tramo_id"])
            except Tramo.DoesNotExist as e:
                print("WARN: " + str(e))
                continue
            Seccion.objects.on_conflict(["id"],ConflictAction.UPDATE).on_conflict(["nombre"],ConflictAction.UPDATE).insert(id=row["id"],nombre=row["nombre"],estacion=estacion,region=region,tramo=tramo)
        else:
            Seccion.objects.on_conflict(["id"],ConflictAction.UPDATE).on_conflict(["nombre"],ConflictAction.UPDATE).insert(id=row["id"],nombre=row["nombre"],estacion=estacion,region=region)

def importTendenciasFromCsv(filename="semanal/static/semanal/csv/tendencias.csv"):
    data = pandas.read_csv(filename,header=0)
    for i, row in data.iterrows():
        Tendencia.objects.on_conflict(["id"],ConflictAction.UPDATE).on_conflict(["nombre"],ConflictAction.UPDATE).insert(id=row["id"],nombre=row["nombre"])


if __name__ == "__main__":
    print("INFO: Realizando importación inicial de datos")
    importRegionesFromGeoJson()
    importTramosFromGeoJson()
    importVariablesFromCsv()
    importSeccionesFromCsv()
    importTendenciasFromCsv()