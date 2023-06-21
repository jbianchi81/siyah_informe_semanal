from django.contrib import admin
from .models import Informe, Contenido, ContenidoTramo, Dato, Tendencia, Region, Tramo, Seccion, Variable, MapaBase
import copy
from datetime import date
from import_export import resources
from import_export.admin import ImportExportModelAdmin
from django.urls import path
from .views import ImportInformeView


# i/o resources

class InformeResource(resources.ModelResource):

    class Meta:
        model = Informe
        import_id_fields = ('fecha',)
        fields = ('fecha','texto_general','revisado')

class ContenidoResource(resources.ModelResource):

    class Meta:
        model = Contenido
        import_id_fields = ('fecha','region')
        fields = ('fecha','region','texto','fecha_actualizado')

class ContenidoTramoResource(resources.ModelResource):

    class Meta:
        model = ContenidoTramo
        import_id_fields = ('fecha','tramo')
        fields = ('fecha','tramo','texto','fecha_actualizado')

class DatoResource(resources.ModelResource):

    class Meta:
        model = Dato
        import_id_fields = ('fecha','seccion','variable')
        fields = ("fecha","seccion","variable","min_obs","mean_obs","max_obs","min_prono","mean_prono","max_prono","tendencia","fecha_actualizado")



# model admins

def copy_informe(modeladmin, request, queryset):
    for informe in queryset:
        nuevo_informe = copy.copy(informe)
        nuevo_informe.fecha = date.today()
        nuevo_informe.revisado = False
        nuevo_informe.save()
        for contenido in informe.contenido_set.all():
            nuevo_contenido = copy.copy(contenido)
            nuevo_contenido.id = None
            nuevo_contenido.fecha = nuevo_informe
            nuevo_contenido.save()
        for contenidotramo in informe.contenidotramo_set.all():
            nuevo_contenidotramo = copy.copy(contenidotramo)
            nuevo_contenidotramo.id = None
            nuevo_contenidotramo.fecha = nuevo_informe
            nuevo_contenidotramo.save()
        for dato in informe.dato_set.all():
            nuevo_dato = copy.copy(dato)
            nuevo_dato.id = None
            nuevo_dato.fecha = nuevo_informe
            nuevo_dato.save()
        nuevo_informe.save()

copy_informe.short_description = "Copiar el contenido de los informes seleccionados a un nuevo informe con la fecha actual"

class ContenidoInline(admin.StackedInline):
    model = Contenido
    extra = 1

class ContenidoTramoInline(admin.StackedInline):
    model = ContenidoTramo
    extra = 1

class DatoInline(admin.TabularInline):
    model = Dato
    extra = 1

class InformeAdmin(ImportExportModelAdmin): #admin.ModelAdmin):
    resource_class = InformeResource
    change_list_template = "admin/semanal/informe/change_list.html"
    def delete_selected(self, request, queryset):
        for informe in queryset:
            print(informe.fecha)
            informe.fecha = informe.fecha.isoformat()
        super().delete_queryset(request,queryset)
    delete_selected.short_description = "Eliminar informes seleccionados"
    def get_readonly_fields(self, request, obj=None):
        if obj:
            return self.readonly_fields + ('fecha',)
        return self.readonly_fields
    fieldsets = [
        (None, {'fields': ['fecha','texto_general','revisado']}),
    ]
    # readonly_fields = ['fecha']
    inlines = [ContenidoInline, ContenidoTramoInline, DatoInline]
    list_display = ('fechaIsoFormat', 'isLast', 'contenidoLength', 'contenidoTramoLength','datoLength','revisado')
    list_filter = ('fecha',)
    search_fields = ('fecha',)
    actions = [delete_selected,copy_informe]
    # def get_urls(self):
    #     urls = super(InformeAdmin,self).get_urls()
    #     my_urls = [path('',self.admin_site.admin_view(ImportInformeView.as_view()))]
    #     return my_urls + urls

class TendenciaAdmin(admin.ModelAdmin):
    list_display = ('id','nombre')
    search_fields = ('nombre',)

class SeccionAdmin(admin.ModelAdmin):
    model = Seccion
    list_display = ('id','nombre','estacion_id')
    search_fields = ('nombre',)
    def get_search_results(self, request, queryset, search_term):   # for customize search_list
        queryset,use_distinct = super(SeccionAdmin, self).get_search_results(request,queryset,search_term)
        if len(queryset):
            return queryset, use_distinct
        else:
            print("nombre not found, searching by estacion_id")
            try:
                id = int(search_term)
                queryset = self.model.objects.filter(estacion_id=id)
            except:
                pass
            return queryset, use_distinct

class ContenidoAdmin(ImportExportModelAdmin):
    resource_class = ContenidoResource
    list_filter = ('fecha','region')

class ContenidoTramoAdmin(ImportExportModelAdmin):
    resource_class = ContenidoTramoResource
    list_filter = ('fecha','tramo')

class DatoAdmin(ImportExportModelAdmin):
    resource_class = DatoResource
    list_filter = ('fecha','seccion')

class VariableAdmin(admin.ModelAdmin):
    model = Variable
    list_display = ('id','nombre','var_id','units')
    search_fields = ('nombre','id','var_id','units')

# Register your models here.

admin.site.register(Informe, InformeAdmin)
admin.site.register(Tendencia,TendenciaAdmin)
admin.site.register(Region)
admin.site.register(Tramo)
admin.site.register(Seccion,SeccionAdmin)
admin.site.register(Contenido,ContenidoAdmin)
admin.site.register(ContenidoTramo,ContenidoTramoAdmin)
admin.site.register(Dato,DatoAdmin)
admin.site.register(Variable,VariableAdmin)
admin.site.register(MapaBase)