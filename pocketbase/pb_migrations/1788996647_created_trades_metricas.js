/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    "createRule": "",
    "deleteRule": "",
    "fields": [
      {
        "autogeneratePattern": "[a-z0-9]{15}",
        "help": "",
        "hidden": false,
        "id": "text3208210256",
        "max": 15,
        "min": 15,
        "name": "id",
        "pattern": "^[a-z0-9]+$",
        "presentable": false,
        "primaryKey": true,
        "required": true,
        "system": true,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "help": "",
        "hidden": false,
        "id": "text2715230876",
        "max": 0,
        "min": 0,
        "name": "ticket_mt5",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "help": "",
        "hidden": false,
        "id": "text1759206190",
        "max": 0,
        "min": 0,
        "name": "canal_id",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "help": "",
        "hidden": false,
        "id": "text1767766964",
        "max": 0,
        "min": 0,
        "name": "par",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "help": "",
        "hidden": false,
        "id": "select2315445172",
        "maxSelect": 1,
        "name": "accion",
        "presentable": false,
        "required": false,
        "system": false,
        "type": "select",
        "values": [
          "BUY",
          "SELL"
        ]
      },
      {
        "help": "",
        "hidden": false,
        "id": "number3658747448",
        "max": null,
        "min": null,
        "name": "lotaje",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "help": "",
        "hidden": false,
        "id": "number4004517315",
        "max": null,
        "min": null,
        "name": "precio_entrada",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "help": "",
        "hidden": false,
        "id": "number885510934",
        "max": null,
        "min": null,
        "name": "stop_loss",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "help": "",
        "hidden": false,
        "id": "number3431029833",
        "max": null,
        "min": null,
        "name": "take_profit",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "help": "",
        "hidden": false,
        "id": "number724230582",
        "max": null,
        "min": null,
        "name": "precio_cierre",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "help": "",
        "hidden": false,
        "id": "number2248929235",
        "max": null,
        "min": null,
        "name": "profit_usd",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "help": "",
        "hidden": false,
        "id": "number3947812447",
        "max": null,
        "min": null,
        "name": "pips",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "help": "",
        "hidden": false,
        "id": "select1960953236",
        "maxSelect": 1,
        "name": "estado_trade",
        "presentable": false,
        "required": false,
        "system": false,
        "type": "select",
        "values": [
          "ABIERTO",
          "CERRADO"
        ]
      }
    ],
    "id": "pbc_1863148920",
    "indexes": [],
    "listRule": "",
    "name": "trades_metricas",
    "system": false,
    "type": "base",
    "updateRule": "",
    "viewRule": ""
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_1863148920");

  return app.delete(collection);
})
