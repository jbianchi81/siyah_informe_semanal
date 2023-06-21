from django.http import HttpResponse, Http404, HttpResponseRedirect, HttpResponseBadRequest
from .models import Informe, Contenido, ContenidoTramo, Dato, Region, Tramo, Seccion, Variable, Tendencia, MapaBase
from django.template import loader
from django.shortcuts import render, get_list_or_404, get_object_or_404, redirect
from django.urls import reverse
from django.views import generic, View
from jsonview.decorators import json_view
import json
import re
from django import forms
import django_excel as excel
from django.contrib.auth.decorators import user_passes_test, login_required

settings = {
    "static_absolute_url": "https://alerta.ina.gob.ar/siyah_informes/static"
}

# FORMS


class IndexView(generic.ListView):
    template_name = 'semanal/index.html'
    context_object_name = 'latest_informe_list'

    def get_queryset(self):
        """Return the last five published informes."""
        latest_informe_list = Informe.objects.order_by('-fecha')[:5]
        for informe in latest_informe_list:
            informe.fecha_iso = informe.fecha.isoformat()
        return latest_informe_list

# def index(request):
#     latest_informe_list = get_list_or_404(Informe.objects.order_by('-fecha'))[:5]
#     for informe in latest_informe_list:
#         informe.fecha_iso = informe.fecha.isoformat()
#     template = loader.get_template('semanal/index.html')
#     context = {
#         'latest_informe_list': latest_informe_list,
#     }
#     return render(request,'semanal/index.html',context) # HttpResponse(template.render(context, request))

class InformeView(generic.DetailView):
    model = Informe
    template_name = "semanal/informe.html"

def informe(request,fecha):
    informe = get_object_or_404(Informe,pk=fecha)
    # try:
    #     informe = Informe.objects.get(pk=fecha)
    # except Informe.DoesNotExist as e:
    #         return Http404("Error: " + str(e))
    # template = loader.get_template('semanal/informe.html')
    informe.fecha_iso = informe.fecha.isoformat()
    context = {
        'informe': informe
        # 'contenido_list': informe.contenido_set.all(),
        # 'contenidotramo_list': informe.contenidotramo_set.all()
    }
    return render(request,'semanal/informe.html',context) # HttpResponse(template.render(context, request))

def contenido(request,fecha,region_id):
    contenido = get_object_or_404(Contenido,fecha=fecha,region_id=region_id)
    if request.method == "GET":
        contenido.fecha_actualizado_iso = contenido.fecha_actualizado.isoformat()
        context = {
            'contenido': contenido
        }
        return render(request,'semanal/contenido.html',context)
    elif request.method == "POST":
        try:
            new_texto = request.POST["texto"]
            new_fecha_actualizado = request.POST["fecha_actualizado"]
        except KeyError:
            context = {
                'contenido': contenido,
                'error_message': 'Falta el texto'
            }
            return render(request,'semanal/contenido.html',context)
        else:
            contenido.texto = new_texto
            contenido.fecha_actualizado = new_fecha_actualizado
            contenido.save()
            return HttpResponseRedirect(reverse('semanal:informe', args=(contenido.fecha,)))

# API

@json_view
def api_regiones(request):
    regiones = get_list_or_404(Region)
    geojson = {
        "type": "FeatureCollection",
        "features": []
    }
    for region in regiones:
        geojson["features"].append({
            "type": "Feature",
            "id": region.id,
            "geometry": region.geom,
            "properties": {
                "id": region.id,
                "nombre": region.nombre
            }
        })
    return geojson

@json_view
def api_region(request,pk):
    region = get_object_or_404(Region,id=pk)
    geojson = {
        "type": "Feature",
        "id": region.id,
        "geometry": region.geom,
        "properties": {
            "id": region.id,
            "nombre": region.nombre
        }
    }
    return geojson

@json_view
def api_tramos(request):
    tramos = get_list_or_404(Tramo)
    geojson = {
        "type": "FeatureCollection",
        "features": []
    }
    for tramo in tramos:
        geojson["features"].append({
            "type": "Feature",
            "id": tramo.id,
            "geometry": tramo.geom,
            "properties": {
                "id": tramo.id,
                "region_id": tramo.region_id,
                "nombre": tramo.nombre
            }
        })
    return geojson

@json_view
def api_tramo(request,pk):
    tramo = get_object_or_404(Tramo,id=pk)
    geojson = {
        "type": "Feature",
        "id": tramo.id,
        "geometry": tramo.geom,
        "properties": {
            "id": tramo.id,
            "region_id": tramo.region_id,
            "nombre": tramo.nombre
        }
    }
    return geojson

@json_view
def api_secciones(request):
    secciones = get_list_or_404(Seccion)
    geojson = {
        "type": "FeatureCollection",
        "features": []
    }
    for seccion in secciones:
        geojson["features"].append({
            "type": "Feature",
            "id": seccion.id,
            "geometry": json.loads(seccion.estacion.geom.geojson),
            "properties": {
                "id": seccion.id,
                "nombre": seccion.nombre,
                "estacion_id": seccion.estacion.unid,
                "region_id": seccion.region.id if seccion.region is not None else None,
                "tramo_id": seccion.tramo.id if seccion.tramo is not None else None
            }
        })
    return geojson

@json_view
def api_seccion(request,pk):
    seccion = get_object_or_404(Seccion,id=pk)
    geojson = {
        "type": "Feature",
        "id": seccion.id,
        "geometry": json.loads(seccion.estacion.geom.geojson),
        "properties": {
            "id": seccion.id,
            "nombre": seccion.nombre,
            "estacion_id": seccion.estacion.unid,
            "region_id": seccion.region.id if seccion.region is not None else None,
            "tramo_id": seccion.tramo.id if seccion.tramo is not None else None        
        }
    }
    return geojson

@json_view
def api_informe(request,pk=None):
    if pk is None:
        informe = get_list_or_404(Informe,revisado=True)[0]
    else:
        print("pk: %s (%s)" % (str(pk),type(pk)))
        match = re.match("\d{4}\-\d{1,2}\-\d{1,2}",pk)        
        if match is None:
            raise Http404("Sintaxis inválida para fecha. Debe ser YYYY-MM-DD")
        informe = get_object_or_404(Informe,fecha=match.string)
    informe_dict = informe.to_dict()
    # add png image url
    informe_dict["map_image_url"] = "%s/semanal/png/CDP.png" % settings["static_absolute_url"]
    region_ids = []
    for region in informe_dict["contenido"]:
        region_ids.append(region["region_id"])
        region["map_image_url"] = "%s/semanal/png/%s.png" % (settings["static_absolute_url"], region["region_id"])
    regiones = get_list_or_404(Region)
    # adding missing regions
    for region in regiones:
        if region.id not in region_ids:
            informe_dict["contenido"].append({
                "region_id": region.id,
                "region": region.nombre,
                "map_image_url": "%s/semanal/png/%s.png" % (settings["static_absolute_url"], region.id)
            })
    return informe_dict

@json_view
def api_mapas(request):
    mapas = get_list_or_404(MapaBase)
    return [mapa.to_dict() for mapa in mapas]

# IMPORT XLS

class UploadFileForm(forms.Form):
    file = forms.FileField()

# @login_required
# @user_passes_test(lambda u: u.groups.filter(name='redactor').count() > 0, login_url='/denied')
class ImportInformeView(View):
    #def import_informe(request):
    fecha = None
    def informe_func(self,row):
        self.fecha = row[0]
        return row
    def contenido_func(self,row):
        if self.fecha is None:
            raise Exception("Fecha is None")
        informe = Informe.objects.filter(fecha=self.fecha)[0]
        # row[0] = informe
        region = Region.objects.filter(id=row[0])
        if not len(region):
            raise Http404("No se encontró region_id=%s" % row[0])
        region = region[0]
        # row[0] = region
        contenido = Contenido.objects.filter(fecha=informe,region=region)
        if len(contenido):
            contenido = contenido[0]
            contenido.texto = row[1]
            contenido.fecha_actualizado = row[2]
            contenido.save()
            return None
        contenido = Contenido(fecha=informe,region=region,texto=row[1],fecha_actualizado=row[2])
        contenido.save()
        return None

    def contenidotramo_func(self,row):
        informe = Informe.objects.filter(fecha=self.fecha)[0]
        # row[0] = informe
        tramo = Tramo.objects.filter(id=row[0])[0]
        # row[0] = tramo
        contenidotramo = ContenidoTramo.objects.filter(fecha=informe,tramo=tramo)
        if len(contenidotramo):
            contenidotramo = contenidotramo[0]
            contenidotramo.texto = row[1]
            contenidotramo.fecha_actualizado = row[2]
            contenidotramo.save()
            return None
        contenidotramo = ContenidoTramo(fecha=informe,tramo=tramo,texto=row[1],fecha_actualizado=row[2])
        contenidotramo.save()
        return None

    def dato_func(self,row):
        informe = Informe.objects.filter(fecha=self.fecha)[0]
        # row[0] = informe
        seccion = Seccion.objects.filter(id=row[0])[0]
        # row[1] = seccion
        variable = Variable.objects.filter(id=row[1])[0]
        # row[2] = variable
        if row[8]:
            tendencia_match = Tendencia.objects.filter(id=row[8])
            if(len(tendencia_match)):
                row[8] = tendencia_match[0]
            else:
                Warning("Tendencia %s not found" % row[8])
                row[8] = None
        else:
            row[8] = None
        dato = Dato.objects.filter(fecha=informe,seccion=seccion,variable=variable)
        if len(dato):
            dato = dato[0]
            row_number = 2
            for field in ["min_obs","mean_obs","max_obs","min_prono","mean_prono","max_prono","tendencia","fecha_actualizado"]:
                setattr(dato,field,row[row_number])
                row_number = row_number + 1
            dato.save()
            return None
        dato = Dato(fecha=informe,seccion=seccion,variable=variable)
        row_number = 2
        for field in ["min_obs","mean_obs","max_obs","min_prono","mean_prono","max_prono","tendencia","fecha_actualizado"]:
            setattr(dato,field,row[row_number])
            row_number = row_number + 1
        dato.save()
        return None
    
    def post(self,request):
        # if request.method == "POST":
        form = UploadFileForm(request.POST, request.FILES)
        self.fecha = None
    
        if form.is_valid():
            request.FILES["file"].save_book_to_database(
                models=[Informe, Contenido, ContenidoTramo, Dato],
                initializers=[self.informe_func, self.contenido_func, self.contenidotramo_func, self.dato_func],
                mapdicts=[
                    ['fecha','texto_general','revisado'],
                    ['region','texto','fecha_actualizado'],
                    ['tramo','texto','fecha_actualizado'],
                    ["seccion","variable","min_obs","mean_obs","max_obs","min_prono","mean_prono","max_prono","tendencia","fecha_actualizado"]
                ],
            )
            return redirect("semanal:informe_handson_table_view", pk = self.fecha)
        else:
            return HttpResponseBadRequest()
    def get(self,request):
        form = UploadFileForm()
        return render(
            request,
            "semanal/informe_upload_form.html",
            {
                "form": form,
                "title": "Importar planilla excel de informe",
                "header": "Please upload informe.xls:",
            },
        )

@login_required
@user_passes_test(lambda u: u.groups.filter(name='redactor').count() > 0, login_url='/denied')
def informe_handson_table(request):
    return excel.make_response_from_tables(
        [Informe, Contenido, ContenidoTramo, Dato], "handsontable.html"
    )

@login_required
@user_passes_test(lambda u: u.groups.filter(name='redactor').count() > 0, login_url='/denied')
def embed_informe_handson_table(request):
    content = excel.pe.save_book_as(
        models=[Informe, Contenido, ContenidoTramo, Dato],
        dest_file_type="handsontable.html",
        dest_embed=True,
    )
    content.seek(0)
    return render(
        request,
        "semanal/informe_handsontable.html",
        {"handsontable_content": content.read()},
    )

def informe_handson_table_view(request,pk):
    file_format = str.lower(request.GET.get("format","handsontable.html"))
    if file_format not in ["csv","tsv","csvz","tsvz","ods","handsontable.html"]: # "xls","xlsx","xlsm"
        return HttpResponseBadRequest('Formato solicitado no válido. Opciones: "csv","tsv","csvz","tsvz","ods","handsontable.html"')
    informe = get_list_or_404(Informe,fecha=pk)
    informe_bookdict = informe[0].to_bookdict()
    if file_format == "handsontable.html":
        content = excel.pe.save_book_as(
            bookdict = informe_bookdict,
            dest_file_type="handsontable.html",
            dest_embed=True,
        )
        content.seek(0)
        return render(
            request,
            "semanal/informe_handsontable.html",
            {"handsontable_content": content.read(), "fecha": informe[0].fecha.isoformat()},
        )
    else:
        return excel.make_response_from_book_dict(
            informe_bookdict, 
            file_format, 
            200
        )

@login_required
@user_passes_test(lambda u: u.groups.filter(name='redactor').count() > 0, login_url='/denied')
def imports(request):
    return render(request, "semanal/imports.html",{})
# def embed_informe_handson_table_fecha(request,pk):
#     informe = get_object_or_404(Informe,pk=fecha)
#     content = excel.pe.save_book_as(
#         models=[Informe, Contenido, ContenidoTramo, Dato],
#         dest_file_type="handsontable.html",
#         dest_embed=True,
#     )
#     content.seek(0)
#     return render(
#         request,
#         "semanal/informe_handsontable.html",
#         {"handsontable_content": content.read()},
#     )